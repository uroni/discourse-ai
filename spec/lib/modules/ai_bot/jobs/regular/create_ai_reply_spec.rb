# frozen_string_literal: true

require_relative "../../../../../support/openai_completions_inference_stubs"

RSpec.describe Jobs::CreateAiReply do
  describe "#execute" do
    fab!(:topic) { Fabricate(:topic) }
    fab!(:post) { Fabricate(:post, topic: topic) }

    let(:expected_response) do
      "Hello this is a bot and what you just said is an interesting question"
    end
    let(:deltas) { expected_response.split(" ").map { |w| { content: "#{w} " } } }

    before do
      SiteSetting.min_personal_message_post_length = 5

      OpenAiCompletionsInferenceStubs.stub_streamed_response(
        CompletionPrompt.bot_prompt_with_topic_context(post),
        deltas,
        req_opts: {
          temperature: 0.4,
          top_p: 0.9,
          max_tokens: 3000,
          stream: true,
        },
      )
    end

    it "adds a reply from the GPT bot" do
      subject.execute(post_id: topic.first_post.id)

      expect(topic.posts.last.raw).to eq(expected_response)
    end

    it "streams the reply on the fly to the client through MB" do
      messages =
        MessageBus.track_publish("discourse-ai/ai-bot/topic/#{topic.id}") do
          subject.execute(post_id: topic.first_post.id)
        end

      done_signal = messages.pop

      expect(messages.length).to eq(deltas.length)

      messages.each_with_index do |m, idx|
        expect(m.data[:raw]).to eq(deltas[0..(idx + 1)].map { |d| d[:content] }.join)
      end

      expect(done_signal.data[:done]).to eq(true)
    end
  end
end