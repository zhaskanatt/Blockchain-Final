import { useEffect, useState } from 'react'

const SUBGRAPH_URL = 'http://localhost:8000/subgraphs/name/prediction-market'

const QUERY = `
{
  proposals(first: 10) {
    id
    proposer
    description
    createdAtTimestamp
  }
  votes(first: 10) {
    id
    proposalId
    voter
    support
    weight
  }
  markets(first: 10) {
    id
    marketAddress
    index
  }
}
`

export default function SubgraphPanel() {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')

  async function loadSubgraphData() {
    try {
      setError('')

      const res = await fetch(SUBGRAPH_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query: QUERY }),
      })

      const json = await res.json()

      if (json.errors) {
        setError(json.errors[0].message)
        return
      }

      setData(json.data)
    } catch {
      setError('Subgraph is not running or endpoint is unavailable.')
    }
  }

  useEffect(() => {
    loadSubgraphData()
  }, [])

  return (
    <div style={{ marginTop: '40px' }}>
      <h2>Subgraph Data</h2>

      <button onClick={loadSubgraphData}>Refresh Subgraph Data</button>

      {error && <p style={{ color: 'red' }}>{error}</p>}

      <h3>Proposals</h3>
      {data?.proposals?.length ? (
        data.proposals.map((p) => (
          <div key={p.id}>
            <p><strong>ID:</strong> {p.id}</p>
            <p><strong>Proposer:</strong> {p.proposer}</p>
            <p><strong>Description:</strong> {p.description}</p>
            <hr />
          </div>
        ))
      ) : (
        <p>No indexed proposals yet.</p>
      )}

      <h3>Votes</h3>
      {data?.votes?.length ? (
        data.votes.map((v) => (
          <div key={v.id}>
            <p><strong>Proposal:</strong> {v.proposalId}</p>
            <p><strong>Voter:</strong> {v.voter}</p>
            <p><strong>Support:</strong> {v.support}</p>
            <p><strong>Weight:</strong> {v.weight}</p>
            <hr />
          </div>
        ))
      ) : (
        <p>No indexed votes yet.</p>
      )}

      <h3>Markets</h3>
      {data?.markets?.length ? (
        data.markets.map((m) => (
          <div key={m.id}>
            <p><strong>Market:</strong> {m.marketAddress}</p>
            <p><strong>Index:</strong> {m.index}</p>
            <hr />
          </div>
        ))
      ) : (
        <p>No indexed markets yet.</p>
      )}
    </div>
  )
}