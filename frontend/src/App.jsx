import WalletConnect from './components/WalletConnect'
import NetworkWarning from './components/NetworkWarning'
import TokenInfo from './components/TokenInfo'
import GovernancePanel from './components/GovernancePanel'
import VaultPanel from './components/VaultPanel'
import MarketPanel from './components/MarketPanel'
import SubgraphPanel from './components/SubgraphPanel'

function App() {
  return (
    <div
      style={{
        padding: '40px',
        fontFamily: 'Arial',
      }}
    >
      <h1>Prediction Market DAO</h1>

      <WalletConnect />

      <NetworkWarning />

      <TokenInfo />

      <GovernancePanel />

      <VaultPanel />

      <MarketPanel />

      <SubgraphPanel />
    </div>
  )
}

export default App