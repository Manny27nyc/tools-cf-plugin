require "spec_helper"

describe CFTools::DEAAds do
  let(:client) { fake_client }

  before { stub_client }

  before do
    stub(NATS).start.yields
    stub(NATS).subscribe
    stub(EM).add_periodic_timer.yields
  end

  it "subscribes to dea.advertise" do
    mock(NATS).subscribe("dea.advertise")
    cf %W[dea-ads]
  end

  it "refreshes every 3 seconds" do
    mock(EM).add_periodic_timer(3).yields
    mock.instance_of(described_class).render_table
    cf %W[dea-ads]
  end

  context "when no NATS server info is specified" do
    it "connects on nats:nats@127.0.0.1:4222" do
      mock(NATS).start(hash_including(
        :uri => "nats://nats:nats@127.0.0.1:4222"))

      cf %W[dea-ads]
    end
  end

  context "when NATS server info is specified" do
    it "connects to the given location using the given credentials" do
      mock(NATS).start(hash_including(
        :uri => "nats://someuser:somepass@example.com:4242"))

      cf %W[dea-ads -h example.com -P 4242 -u someuser -p somepass]
    end
  end

  it "prints the table header" do
    cf %W[dea-ads]
    expect(output).to say(/dea\s+stacks\s+droplets\s+available memory/)
  end

  context "when a dea.advertise is seen" do
    let(:advertise) { <<PAYLOAD }
{
  "app_id_to_count": {
    "id1": 2,
    "id2": 1,
    "id3": 3
  },
  "available_memory": 1256,
  "stacks": [
    "lucid64",
    "lucid86"
  ],
  "prod": false,
  "id": "2-1d0cf3bcd994d9f2c5ea22b9b624d77b"
}
PAYLOAD

    before do
      stub(NATS).subscribe.yields(advertise)
    end

    it "prints its entry in the table" do
      cf %W[dea-ads]
      expect(output).to say(/^2\s+lucid64, lucid86\s+6\s+1256$/)
    end

    context "and another advertise is seen" do
      before do
        stub(NATS).subscribe do |_, blk|
          blk.call(advertise)
          blk.call(other_advertise)
        end
      end

      context "from a different DEA" do
        let(:other_advertise) { <<PAYLOAD }
{
  "app_id_to_count": {
    "id2": 3,
    "id3": 1,
    "id4": 1
  },
  "available_memory": 1024,
  "stacks": [
    "lucid64"
  ],
  "prod": false,
  "id": "3-1d0cf3bcd994d9f2c5ea22b9b624d77b"
}
PAYLOAD

        it "prints its entry in the table" do
          cf %W[dea-ads]
          expect(output).to say(/^3\s+lucid64\s+5\s+1024$/)
        end

        it "keeps the other entry in the table" do
          cf %W[dea-ads]
          expect(output).to say(/^2\s+lucid64, lucid86\s+6\s+1256$/)
        end

        it "sorts the rows by DEA index" do
          cf %W[dea-ads]
          expect(output).to say(/^2\s+.*\n^3/)
        end
      end

      context "from the same DEA" do
        let(:other_advertise) { <<PAYLOAD }
{
  "app_id_to_count": {
    "id1": 1,
    "id2": 1,
    "id3": 3
  },
  "available_memory": 1000,
  "stacks": [
    "lucid64"
  ],
  "prod": false,
  "id": "2-1d0cf3bcd994d9f2c5ea22b9b624d77b"
}
PAYLOAD

        it "clears the original entry" do
          cf %W[dea-ads]
          expect(output).to_not say("1256")
        end

        it "shows the difference from the last advertisement" do
          cf %W[dea-ads]
          expect(output).to say(/^2\s+lucid64\s+5 \(-1\)\s+1000 \(-256\)$/)
        end
      end
    end
  end
end
