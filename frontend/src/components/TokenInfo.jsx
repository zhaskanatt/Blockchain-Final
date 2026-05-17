import { useAccount, useReadContract } from 'wagmi'
import { formatUnits } from 'viem'

import governanceArtifact from '../abi/GovernanceToken.json'
import { CONTRACTS } from '../config/contracts'

import DelegateButton from './DelegateButton'

const governanceAbi = governanceArtifact.abi ?? governanceArtifact

export default function TokenInfo() {
  const { address, chainId } = useAccount()

  const {
    data: balance,
    error: balanceError,
    isLoading: balanceLoading,
  } = useReadContract({
    address: CONTRACTS.governanceToken,
    abi: governanceAbi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: Boolean(address),
    },
  })

  const {
    data: votingPower,
    error: votesError,
    isLoading: votesLoading,
  } = useReadContract({
    address: CONTRACTS.governanceToken,
    abi: governanceAbi,
    functionName: 'getVotes',
    args: address ? [address] : undefined,
    query: {
      enabled: Boolean(address),
    },
  })

  const {
    data: delegate,
    error: delegateError,
    isLoading: delegateLoading,
  } = useReadContract({
    address: CONTRACTS.governanceToken,
    abi: governanceAbi,
    functionName: 'delegates',
    args: address ? [address] : undefined,
    query: {
      enabled: Boolean(address),
    },
  })

  return (
    <div style={{ marginTop: '30px' }}>
      <h2>Governance Token</h2>

      <p>Connected wallet: {address || 'Not connected'}</p>
      <p>Chain ID: {chainId}</p>
      <p>Token contract: {CONTRACTS.governanceToken}</p>

      <p>
        Balance:{' '}
        {balanceLoading
          ? 'Loading...'
          : balance !== undefined
            ? formatUnits(balance, 18)
            : '0'}{' '}
        PDAO
      </p>

      <p>
        Voting Power:{' '}
        {votesLoading
          ? 'Loading...'
          : votingPower !== undefined
            ? formatUnits(votingPower, 18)
            : '0'}
      </p>

      <p>
        Delegate:{' '}
        {delegateLoading ? 'Loading...' : delegate || 'Not delegated'}
      </p>

      {balanceError && <p style={{ color: 'red' }}>Balance error: {balanceError.shortMessage || balanceError.message}</p>}
      {votesError && <p style={{ color: 'red' }}>Votes error: {votesError.shortMessage || votesError.message}</p>}
      {delegateError && <p style={{ color: 'red' }}>Delegate error: {delegateError.shortMessage || delegateError.message}</p>}

      <DelegateButton />
    </div>
  )
}