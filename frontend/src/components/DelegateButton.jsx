import { useState } from 'react'
import { useAccount, useWriteContract } from 'wagmi'

import governanceArtifact from '../abi/GovernanceToken.json'
import { CONTRACTS } from '../config/contracts'

const governanceAbi = governanceArtifact.abi ?? governanceArtifact

export default function DelegateButton() {
  const { address } = useAccount()
  const { writeContractAsync, isPending } = useWriteContract()

  const [message, setMessage] = useState('')

  async function handleDelegate() {
    try {
      setMessage('Confirm transaction in MetaMask...')

      const txHash = await writeContractAsync({
        address: CONTRACTS.governanceToken,
        abi: governanceAbi,
        functionName: 'delegate',
        args: [address],
      })

      setMessage(`Delegation sent: ${txHash}`)
    } catch (err) {
      console.error(err)

      if (err.message?.includes('User rejected')) {
        setMessage('Transaction rejected by user.')
      } else {
        setMessage(err.shortMessage || err.message || 'Transaction failed.')
      }
    }
  }

  return (
    <div style={{ marginTop: '20px' }}>
      <button onClick={handleDelegate} disabled={!address || isPending}>
        {isPending ? 'Delegating...' : 'Delegate to myself'}
      </button>

      {message && <p>{message}</p>}
    </div>
  )
}