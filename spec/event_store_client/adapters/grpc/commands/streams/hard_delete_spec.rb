# frozen_string_literal: true

RSpec.describe EventStoreClient::GRPC::Commands::Streams::HardDelete do
  let(:instance) { described_class.new }

  it { is_expected.to be_a(EventStoreClient::GRPC::Commands::Command) }
  it 'uses correct params class' do
    expect(instance.request).to eq(EventStore::Client::Streams::TombstoneReq)
  end
  it 'uses correct service' do
    expect(instance.service).to be_a(EventStore::Client::Streams::Streams::Stub)
  end

  describe '#call' do
    subject { instance.call(stream_name, options: {}) }

    let(:stream_name) { "some-stream$#{SecureRandom.uuid}" }

    describe 'deleting existing stream' do
      let(:event) do
        EventStoreClient::DeserializedEvent.new(
          id: SecureRandom.uuid, type: 'some-event', data: { foo: :bar }
        )
      end

      before do
        EventStoreClient.client.append_to_stream(stream_name, event)
      end

      it 'deletes stream' do
        expect { subject }.to change {
          EventStoreClient.client.read(stream_name)
        }.from(be_success).to(Dry::Monads::Failure(:stream_not_found))
      end
      it { is_expected.to be_success }
    end

    describe 'deleting non-existing stream' do
      it 'returns failure' do
        is_expected.to be_failure
      end
      it 'returns correct failure message' do
        expect(subject.failure).to eq(:stream_not_found)
      end
    end
  end
end
