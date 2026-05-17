import { useState } from 'react'
import { encodeFunctionData, parseEther } from 'viem'
import { useAccount, useWriteContract } from 'wagmi'

import governorArtifact from '../abi/PredictionGovernor.json'
import treasuryArtifact from '../abi/Treasury.json'
import { CONTRACTS } from '../config/contracts'

const governorAbi = governorArtifact.abi ?? governorArtifact
const treasuryAbi = treasuryArtifact.abi ?? treasuryArtifact

export default function CreateProposalButton() {
  const { address } = useAccount()
  const { writeContractAsync, isPending } = useWriteContract()
  const [message, setMessage] = useState('')

  async function createProposal() {
    try {
      setMessage('Confirm proposal transaction...')

      const calldata = encodeFunctionData({
        abi: treasuryAbi,
        functionName: 'releaseETH',
        args: [address, parseEther('0.001')],
      })

      const txHash = await writeContractAsync({
        address: CONTRACTS.governor,
        abi: governorAbi,
        functionName: 'propose',
        args: [
          [CONTRACTS.treasury],
          [0n],
          [calldata],
          'Release 0.001 ETH from treasury to proposer',
        ],
      })

      setMessage(`Proposal transaction sent: ${txHash}`)
    } catch (err) {
      console.error(err)
      setMessage(err.shortMessage || err.message || 'Proposal failed.')
    }
  }

  return (
    <div style={{ marginTop: '20px' }}>
      <button disabled={!address || isPending} onClick={createProposal}>
        {isPending ? 'Creating...' : 'Create test proposal'}
      </button>

      {message && <p>{message}</p>}
    </div>
  )
}