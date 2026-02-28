import { ChatProvider } from './state/ChatContext'
import { ChatScreen } from './components/ChatScreen/ChatScreen'

export default function App() {
  return (
    <ChatProvider>
      <ChatScreen />
    </ChatProvider>
  )
}
