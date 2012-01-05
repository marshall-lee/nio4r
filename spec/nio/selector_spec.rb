require 'spec_helper'

# Timeouts should be at least this precise (in seconds) to pass the tests
# Typical precision should be better than this, but if it's worse it will fail
# the tests
TIMEOUT_PRECISION = 0.1

describe NIO::Selector do
  it "monitors IO objects" do
    pipe, _ = IO.pipe

    monitor = subject.register(pipe, :r)
    monitor.should_not be_closed
  end

  it "knows which IO objects are registered" do
    reader, writer = IO.pipe
    subject.register(reader, :r)

    subject.should be_registered(reader)
    subject.should_not be_registered(writer)
  end

  it "deregisters IO objects" do
    pipe, _ = IO.pipe

    subject.register(pipe, :r)
    monitor = subject.deregister(pipe)
    subject.should_not be_registered(pipe)
    monitor.should be_closed
  end

  context "select" do
    it "waits for a timeout when selecting" do
      reader, writer = IO.pipe
      monitor = subject.register(reader, :r)

      payload = "hi there"
      writer << payload

      timeout = 0.5
      started_at = Time.now
      subject.select(timeout).should include monitor
      (Time.now - started_at).should be_within(TIMEOUT_PRECISION).of(0)
      reader.read_nonblock(payload.size)

      started_at = Time.now
      subject.select(timeout).should be_nil
      (Time.now - started_at).should be_within(TIMEOUT_PRECISION).of(timeout)
    end

    it "wakes up if signaled to from another thread" do
      pipe, _ = IO.pipe
      subject.register(pipe, :r)

      thread = Thread.new do
        started_at = Time.now
        subject.select.should be_nil
        Time.now - started_at
      end

      timeout = 0.1
      sleep timeout
      subject.wakeup

      thread.value.should be_within(TIMEOUT_PRECISION).of(timeout)
    end
  end
  
  context "select_each" do
    it "iterates across ready selectables" do
      readable1, writer = IO.pipe
      writer << "ohai"
    
      readable2, writer = IO.pipe
      writer << "ohai"
    
      unreadable, _ = IO.pipe
    
      monitor1 = subject.register(readable1, :r)
      monitor2 = subject.register(readable2, :r)
      monitor3 = subject.register(unreadable, :r)
    
      readables = []
      subject.select_each { |monitor| readables << monitor }
      
      readables.should include(monitor1)
      readables.should include(monitor2)
      readables.should_not include(monitor3)
    end
  end

  it "closes" do
    subject.close
    subject.should be_closed
  end

  context "selectables" do
    shared_context "an NIO selectable" do
      it "selects for read readiness" do
        waiting_monitor = subject.register(unreadable_subject, :r)
        ready_monitor   = subject.register(readable_subject, :r)

        ready_monitors = subject.select
        ready_monitors.should include ready_monitor
        ready_monitors.should_not include waiting_monitor
      end

      it "selects for write readiness" do
        waiting_monitor = subject.register(unwritable_subject, :w)
        ready_monitor   = subject.register(writable_subject, :w)

        ready_monitors = subject.select(0.1)

        ready_monitors.should include ready_monitor
        ready_monitors.should_not include waiting_monitor
      end
    end

    context "IO.pipe" do
      let :readable_subject do
        pipe, peer = IO.pipe
        peer << "data"
        pipe
      end

      let :unreadable_subject do
        pipe, _ = IO.pipe
        pipe
      end

      let :writable_subject do
        _, pipe = IO.pipe
        pipe
      end

      let :unwritable_subject do
        reader, pipe = IO.pipe

        begin
          pipe.write_nonblock "JUNK IN THE TUBES"
          _, writers = select [], [pipe], [], 0
        rescue Errno::EPIPE
          break
        end while writers and writers.include? pipe

        pipe
      end

      it_behaves_like "an NIO selectable"
    end

    context TCPSocket do
      let(:tcp_port) { 12345 }

      let :readable_subject do
        server = TCPServer.new("localhost", tcp_port)
        sock = TCPSocket.open("localhost", tcp_port)
        peer = server.accept
        peer << "data"
        sock
      end

      let :unreadable_subject do
        if defined?(JRUBY_VERSION) and ENV['TRAVIS']
          pending "This is sporadically showing up readable on JRuby in CI"
        else
          TCPServer.new("localhost", tcp_port + 1)
          TCPSocket.open("localhost", tcp_port + 1)
        end
      end

      let :writable_subject do
        TCPServer.new("localhost", tcp_port + 2)
        TCPSocket.open("localhost", tcp_port + 2)
      end

      let :unwritable_subject do
        server = TCPServer.new("localhost", tcp_port + 3)
        sock = TCPSocket.open("localhost", tcp_port + 3)
        peer = server.accept

        begin
          sock.write_nonblock "JUNK IN THE TUBES"
          _, writers = select [], [sock], [], 0
        end while writers and writers.include? sock

        sock
      end

      it_behaves_like "an NIO selectable"
    end

    context UDPSocket do
      let(:udp_port) { 23456 }

      let :readable_subject do
        sock = UDPSocket.new
        sock.bind('localhost', udp_port)

        peer = UDPSocket.new
        peer.send("hi there", 0, 'localhost', udp_port)

        sock
      end

      let :unreadable_subject do
        sock = UDPSocket.new
        sock.bind('localhost', udp_port + 1)
        sock
      end

      let :writable_subject do
        pending "come up with a writable UDPSocket example"
      end

      let :unwritable_subject do
        pending "come up with a UDPSocket that's blocked on writing"
      end

      it_behaves_like "an NIO selectable"
    end
  end
end
