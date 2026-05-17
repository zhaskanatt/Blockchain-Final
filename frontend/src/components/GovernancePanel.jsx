import { useState } from 'react'
import { useReadContract, useWriteContract } from 'wagmi'

import governorArtifact from '../abi/PredictionGovernor.json'
import { CONTRACTS } from '../config/contracts'

import CreateProposalButton from './CreateProposalButton'

const governorAbi = governorArtifact.abi ?? governorArtifact

const STATES = [
  'Pending',
  'Active',
  'Canceled',
  'Defeated',
  'Succeeded',
  'Queued',
  'Expired',
  'Executed',
]

export default function GovernancePanel() {
  const [proposalId, setProposalId] = useState('')
  const [message, setMessage] = useState('')

  const { writeContractAsync, isPending } = useWriteContract()

  const { data: proposalState, refetch } = useReadContract({
    address: CONTRACTS.governor,
    abi: governorAbi,
    functionName: 'state',
    args: proposalId ? [BigInt(proposalId)] : undefined,
    query: {
      enabled: Boolean(proposalId),
    },
  })

  async function vote(support) {
    try {
      setMessage('Confirm vote in MetaMask...')

      const txHash = await writeContractAsync({
        address: CONTRACTS.governor,
        abi: governorAbi,
        functionName: 'castVote',
        args: [BigInt(proposalId), support],
      })

      setMessage(`Vote sent: ${txHash}`)
      refetch()
    } catch (err) {
      console.error(err)
      setMessage(err.shortMessage || err.message || 'Vote failed.')
    }
  }

  return (
    <div style={{ marginTop: '40px' }}>
      <h2>Governance</h2>

      <p>Governor contract: {CONTRACTS.governor}</p>

      <CreateProposalButton />

      <div style={{ marginTop: '20px' }}>
        <input
          style={{ width: '520px', padding: '8px' }}
          placeholder="Enter proposalId"
          value={proposalId}
          onChange={(e) => setProposalId(e.target.value)}
        />
      </div>

      <p>
        Proposal State:{' '}
        {proposalState !== undefined
          ? STATES[Number(proposalState)]
          : 'No proposal selected'}
      </p>

      <button disabled={!proposalId || isPending} onClick={() => vote(1)}>
        Vote FOR
      </button>

      <button
        disabled={!proposalId || isPending}
        onClick={() => vote(0)}
        style={{ marginLeft: '10px' }}
      >
        Vote AGAINST
      </button>

      <button
        disabled={!proposalId || isPending}
        onClick={() => vote(2)}
        style={{ marginLeft: '10px' }}
      >
        Abstain
      </button>

      {message && <p>{message}</p>}
    </div>
  )
}