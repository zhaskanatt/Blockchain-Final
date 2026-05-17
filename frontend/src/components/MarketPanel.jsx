import { useReadContract } from 'wagmi'

import factoryArtifact from '../abi/MarketFactory.json'
import { CONTRACTS } from '../config/contracts'

const factoryAbi = factoryArtifact.abi ?? factoryArtifact

export default function MarketPanel() {
  const { data: totalMarkets } = useReadContract({
    address: CONTRACTS.marketFactory,
    abi: factoryAbi,
    functionName: 'totalMarkets',
  })

  const { data: implementation } = useReadContract({
    address: CONTRACTS.marketFactory,
    abi: factoryAbi,
    functionName: 'implementation',
  })

  const { data: collateral } = useReadContract({
    address: CONTRACTS.marketFactory,
    abi: factoryAbi,
    functionName: 'collateral',
  })

  const { data: shareToken } = useReadContract({
    address: CONTRACTS.marketFactory,
    abi: factoryAbi,
    functionName: 'shareToken',
  })

  const { data: feeVault } = useReadContract({
    address: CONTRACTS.marketFactory,
    abi: factoryAbi,
    functionName: 'feeVault',
  })

  return (
    <div style={{ marginTop: '40px' }}>
      <h2>Market Factory</h2>

      <p>Factory contract: {CONTRACTS.marketFactory}</p>
      <p>Total markets: {totalMarkets !== undefined ? totalMarkets.toString() : 'Loading...'}</p>
      <p>Implementation: {implementation || 'Loading...'}</p>
      <p>Collateral: {collateral || 'Loading...'}</p>
      <p>Outcome share token: {shareToken || 'Loading...'}</p>
      <p>Fee vault: {feeVault || 'Loading...'}</p>
    </div>
  )
}