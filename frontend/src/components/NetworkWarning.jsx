import { useAccount, useSwitchChain } from 'wagmi'

const REQUIRED_CHAIN_ID = 31337

export default function NetworkWarning() {
  const { chainId, isConnected } = useAccount()
  const { switchChain } = useSwitchChain()

  if (!isConnected) return null
  if (chainId === REQUIRED_CHAIN_ID) return null

  return (
    <div style={{ marginTop: '20px', padding: '12px', border: '1px solid red' }}>
      <strong>Wrong network.</strong>
      <p>Please switch to Anvil localhost chain 31337.</p>

      <button onClick={() => switchChain({ chainId: REQUIRED_CHAIN_ID })}>
        Switch Network
      </button>
    </div>
  )
}