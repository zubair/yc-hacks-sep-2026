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
          currentUserId: env.session.profile?.id,
          isLoading: model.isLoading,
          errorMessage: model.errorMessage,
          onReply: {
            env.compose.startNewDraft(recipient: conversation.peer)
            path.append(.compose)
          },
          onRefresh: { await model.load() }
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
