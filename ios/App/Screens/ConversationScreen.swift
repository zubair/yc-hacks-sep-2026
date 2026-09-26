import SwiftUI
import PostcardCore
import PostcardUI

struct ConversationScreen: View {
  @Environment(AppEnvironment.self) private var env
  let conversation: PostcardConversation
  @Binding var path: [Route]
  @State private var model: ConversationViewModel?

  var body: some View {
    Group {
      if let model {
        PostcardConversationView(
          messages: model.messages,
          photoURLs: model.photoURLs,
          photoData: model.photoData,
          photoErrors: model.photoErrors,
          isLoading: model.isLoading,
          error: model.errorMessage,
          isDemo: env.mode == .fixture,
          title: conversation.peer.displayName,
          onReply: {
            env.compose.prepareDraft(recipient: conversation.peer)
            path.append(.compose)
          },
          onRefresh: { Task { await model.load() } },
          onRetryPhoto: { id in Task { await model.retryPhoto(id: id) } }
        )
      } else {
        ProgressView()
      }
    }
    .navigationTitle(conversation.peer.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      let model = ConversationViewModel(service: env.service, conversationId: conversation.id)
      self.model = model
      await model.load()
      await model.observeUpdates()
    }
  }
}
