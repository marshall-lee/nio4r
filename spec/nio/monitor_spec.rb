require "spec_helper"

RSpec.describe NIO::Monitor do
  let(:pipes) { IO.pipe }
  let(:reader) { pipes.first }
  let(:writer) { pipes.last }
  let(:selector) { NIO::Selector.new }

  subject    { selector.register(reader, :r) }
  let(:peer) { selector.register(writer, :rw) }
  after      { selector.close }

  it "knows its interests" do
    expect(subject.interests).to eq(:r)
    expect(peer.interests).to eq(:rw)
  end

  it "changes the interest set" do
    expect(peer.interests).not_to eq(:w)
    peer.interests = :w
    expect(peer.interests).to eq(:w)
  end

  it "knows its IO object" do
    expect(subject.io).to eq(reader)
  end

  it "knows its selector" do
    expect(subject.selector).to eq(selector)
  end

  it "stores arbitrary values" do
    subject.value = 42
    expect(subject.value).to eq(42)
  end

  it "knows what operations IO objects are ready for" do
    # For whatever odd reason this breaks unless we eagerly evaluate subject
    reader_monitor = subject
    writer_monitor = peer

    selected = selector.select(0)
    expect(selected).not_to include(reader_monitor)
    expect(selected).to include(writer_monitor)

    expect(writer_monitor.readiness).to eq(:w)
    expect(writer_monitor).not_to be_readable
    expect(writer_monitor).to be_writable

    writer << "loldata"

    selected = selector.select(0)
    expect(selected).to include(reader_monitor)

    expect(reader_monitor.readiness).to eq(:r)
    expect(reader_monitor).to be_readable
    expect(reader_monitor).not_to be_writable
  end

  it "Changes the interest_set on the go" do
    # Only works in CRuby for some reason.
    # As I identified it might be because of the differences between
    # two implementations (JRuby and CRuby)
    # In Jruby we cannot even use the (:W) to register a ReaderMonitor
    # (selector.register(reader, :r)) because of "IllegalArgumentException"
    # coming from Java.
    # But in CRuby implementation there is no such exception rising from the C backend.
    reader_monitor = subject

    selected = selector.select(0)
    expect(selected).to eq(nil)

    reader_monitor.interests = :w
    selected = selector.select(0)
    expect(selected).not_to eq(nil)
    expect(selected).to include(reader_monitor)
  end

  it "closes" do
    expect(subject).not_to be_closed
    expect(selector.registered?(reader)).to be_truthy

    subject.close
    expect(subject).to be_closed
    expect(selector.registered?(reader)).to be_falsey
  end

  it "closes even if the selector has been shutdown" do
    expect(subject).not_to be_closed
    selector.close # forces shutdown
    expect(subject).not_to be_closed
    subject.close
    expect(subject).to be_closed
  end

  it "changes the interest set after monitor closed" do
    # check for changing the interests on the go after closed expected to fail
    expect(subject.interests).not_to eq(:rw)
    subject.close # forced shutdown
    expect { subject.interests = :rw }.to raise_error(TypeError)
  end
end
