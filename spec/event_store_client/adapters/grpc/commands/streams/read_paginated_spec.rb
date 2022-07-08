# frozen_string_literal: true

RSpec.describe EventStoreClient::GRPC::Commands::Streams::ReadPaginated do
  let(:instance) { described_class.new }

  it { is_expected.to be_a(EventStoreClient::GRPC::Commands::Command) }

  describe '#call' do
    subject do
      instance.call(
        stream_name,
        options: options,
        skip_deserialization: skip_deserialization,
        skip_decryption: skip_decryption
      )
    end

    let(:stream_name) { "some-stream$#{SecureRandom.uuid}" }
    let(:options) { {} }
    let(:skip_deserialization) { false }
    let(:skip_decryption) { false }

    it { is_expected.to be_a(Enumerator) }

    context 'when :max_count option is less than 2' do
      let(:options) { { max_count: 1 } }

      it 'raises error' do
        expect { subject.next }.to raise_error(described_class::RecordsLimitError)
      end
    end

    context 'when stream does not exist' do
      it 'returns failure' do
        expect(subject.next).to be_a(Dry::Monads::Failure)
      end
      it 'returns correct failure message' do
        expect(subject.next.failure).to eq(:stream_not_found)
      end
    end

    context 'when stream exists' do
      let(:events) do
        10.times.map do
          EventStoreClient::DeserializedEvent.new(id: SecureRandom.uuid, type: 'some-event')
        end
      end
      let(:options) { { max_count: 9 } }

      before do
        EventStoreClient.client.append_to_stream(stream_name, events)
      end

      it 'returns success' do
        expect(subject.next).to be_success
      end

      context 'when number of events is less than or equal to :max_count option' do
        it 'returns correct amount of records' do
          expect(subject.next.success.size).to eq(9)
        end
        it 'returns the rest on next iteration' do
          subject.next
          expect(subject.next.success.size).to eq(1)
        end

        describe 'returned records in first iteration' do
          subject { super().next.success }

          it 'returns records from the start' do
            ids = subject.map(&:id)
            expect(ids).to eq(events.first(9).map(&:id))
          end
        end

        describe 'returned records in second iteration' do
          subject { super().next; super().next.success }

          it 'returns records from the position, persisted from previous iteration' do
            ids = subject.map(&:id)
            expect(ids).to eq([events.last.id])
          end
        end
      end

      context 'when number of events is greater than or equal to :max_count option' do
        let(:options) { { max_count: 100 } }

        it 'returns all of them in first iteration' do
          expect(subject.next.success.size).to eq(events.size)
        end
      end

      context 'fetching events from the given revision' do
        let(:options) { { max_count: 100, from_revision: 8 } }

        it 'returns events from the given revision' do
          ids = subject.next.success.map(&:id)
          expect(ids).to eq(events[8..].map(&:id))
        end
      end
    end

    describe 'paginating $all stream' do
      subject do
        instance.call(
          stream_name,
          options: options,
          skip_deserialization: skip_deserialization,
          skip_decryption: skip_decryption
        ) do |opts|
          opts.filter = EventStore::Client::Streams::ReadReq::Options::FilterOptions.new(
            {
              stream_identifier: { prefix: [some_stream] },
              count: EventStore::Client::Empty.new
            }
          )
        end
      end

      let(:stream_name) { "$all" }
      let(:some_stream) { "some-stream-1$#{SecureRandom.uuid}" }
      let(:events) do
        10.times.map do
          EventStoreClient::DeserializedEvent.new(id: SecureRandom.uuid, type: 'some-event')
        end
      end
      # Need to re-read events from stream to get commit_position - initially we don't have it
      let(:events_from_es) do
        EventStoreClient.client.read(stream_name, skip_deserialization: true) do |opts|
          opts.filter = EventStore::Client::Streams::ReadReq::Options::FilterOptions.new(
            {
              stream_identifier: { prefix: [some_stream] },
              count: EventStore::Client::Empty.new
            }
          )
        end
      end

      before do
        EventStoreClient.client.append_to_stream(some_stream, events)
      end

      context 'fetching events from the given position' do
        let(:options) do
          {
            max_count: 100,
            from_position: {
              # Take commit_position of second event from the end
              commit_position: events_from_es.success.last(2).first.event.commit_position
            }
          }
        end

        it 'returns events from the given position' do
          ids = subject.next.success.map(&:id)
          expect(ids).to eq(events[8..].map(&:id))
        end
      end
    end
  end
end
