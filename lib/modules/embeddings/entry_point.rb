# frozen_string_literal: true

module DiscourseAi
  module Embeddings
    class EntryPoint
      def load_files
        require_relative "models"
        require_relative "topic"
        require_relative "jobs/regular/generate_embeddings"
        require_relative "semantic_suggested"
      end

      def inject_into(plugin)
        plugin.add_to_class(:topic_view, :related_topics) do
          if !@guardian&.user || topic.private_message? ||
               !SiteSetting.ai_embeddings_semantic_suggested_topics_enabled
            return nil
          end

          @related_topics ||=
            TopicList.new(
              :suggested,
              nil,
              DiscourseAi::Embeddings::SemanticSuggested.candidates_for(topic),
            ).topics
        end

        plugin.register_modifier(
          :topic_view_suggested_topics_options,
        ) do |suggested_options, topic_view|
          related_topics = topic_view.related_topics
          include_random = related_topics.nil? || related_topics.length == 0
          suggested_options.merge(include_random: include_random)
        end

        %i[topic_view TopicViewPosts].each do |serializer|
          plugin.add_to_serializer(serializer, :related_topics) do
            if object.next_page.nil? && !object.topic.private_message? && scope.authenticated?
              object.related_topics.map do |t|
                SuggestedTopicSerializer.new(t, scope: scope, root: false)
              end
            end
          end

          # custom include method so we also check on semantic search
          plugin.add_to_serializer(serializer, :include_related_topics?) do
            plugin.enabled? && SiteSetting.ai_embeddings_semantic_suggested_topics_enabled
          end
        end

        callback =
          Proc.new do |topic|
            if SiteSetting.ai_embeddings_enabled
              Jobs.enqueue(:generate_embeddings, topic_id: topic.id)
            end
          end

        plugin.on(:topic_created, &callback)
        plugin.on(:topic_edited, &callback)

        DiscoursePluginRegistry.register_list_suggested_for_provider(
          SemanticSuggested.method(:build_suggested_topics),
          plugin,
        )
      end
    end
  end
end
