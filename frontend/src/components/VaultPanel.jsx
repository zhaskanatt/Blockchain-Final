import { useState } from 'react'
import { formatUnits, parseUnits } from 'viem'
import { useAccount, useReadContract, useWriteContract } from 'wagmi'

import vaultArtifact from '../abi/FeeVault.json'
import erc20Artifact from '../abi/MockERC20.json'
import { CONTRACTS } from '../config/contracts'

const vaultAbi = vaultArtifact.abi ?? vaultArtifact
const erc20Abi = erc20Artifact.abi ?? erc20Artifact

export default function VaultPanel() {
  const { address } = useAccount()
  const { writeContractAsync, isPending } = useWriteContract()

  const [amount, setAmount] = useState('10')
  const [message, setMessage] = useState('')

  const { data: totalAssets } = useReadContract({
    address: CONTRACTS.vault,
    abi: vaultAbi,
    functionName: 'totalAssets',
  })

  const { data: shares } = useReadContract({
    address: CONTRACTS.vault,
    abi: vaultAbi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  })

  const { data: assetBalance } = useReadContract({
    address: CONTRACTS.collateral,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  })

  async function approveVault() {
    try {
      setMessage('Confirm approve in MetaMask...')

      const txHash = await writeContractAsync({
        address: CONTRACTS.collateral,
        abi: erc20Abi,
        functionName: 'approve',
        args: [CONTRACTS.vault, parseUnits(amount, 18)],
      })

      setMessage(`Approve sent: ${txHash}`)
    } catch (err) {
      console.error(err)
      setMessage(err.shortMessage || err.message || 'Approve failed.')
    }
  }

  async function deposit() {
    try {
      setMessage('Confirm deposit in MetaMask...')

      const txHash = await writeContractAsync({
        address: CONTRACTS.vault,
        abi: vaultAbi,
        functionName: 'deposit',
        args: [parseUnits(amount, 18), address],
      })

      setMessage(`Deposit sent: ${txHash}`)
    } catch (err) {
      console.error(err)
      setMessage(err.shortMessage || err.message || 'Deposit failed.')
    }
  }

  async function redeem() {
    try {
      setMessage('Confirm redeem in MetaMask...')

      const txHash = await writeContractAsync({
        address: CONTRACTS.vault,
        abi: vaultAbi,
        functionName: 'redeem',
        args: [parseUnits(amount, 18), address, address],
      })

      setMessage(`Redeem sent: ${txHash}`)
    } catch (err) {
      console.error(err)
      setMessage(err.shortMessage || err.message || 'Redeem failed.')
    }
  }

  return (
    <div style={{ marginTop: '40px' }}>
      <h2>Fee Vault</h2>

      <p>Vault contract: {CONTRACTS.vault}</p>
      <p>Collateral token: {CONTRACTS.collateral}</p>

      <p>
        Your collateral balance:{' '}
        {assetBalance !== undefined ? formatUnits(assetBalance, 18) : '0'}
      </p>

      <p>
        Your vault shares:{' '}
        {shares !== undefined ? formatUnits(shares, 18) : '0'}
      </p>

      <p>
        Total vault assets:{' '}
        {totalAssets !== undefined ? formatUnits(totalAssets, 18) : '0'}
      </p>

      <input
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        style={{ padding: '8px', width: '160px' }}
      />

      <button onClick={approveVault} disabled={!address || isPending} style={{ marginLeft: '10px' }}>
        Approve
      </button>

      <button onClick={deposit} disabled={!address || isPending} style={{ marginLeft: '10px' }}>
        Deposit
      </button>

      <button onClick={redeem} disabled={!address || isPending} style={{ marginLeft: '10px' }}>
        Redeem
      </button>

      {message && <p>{message}</p>}
    </div>
  )
}