import {
  MarketDeployedCreate,
  MarketDeployedCreate2,
} from "../generated/MarketFactory/MarketFactory"

import {
  ProposalCreated,
  VoteCast,
} from "../generated/PredictionGovernor/PredictionGovernor"

import {
  FeesReceived,
} from "../generated/FeeVault/FeeVault"

import {
  Market,
  Create2Market,
  Proposal,
  Vote,
  VaultFee,
} from "../generated/schema"

export function handleMarketDeployedCreate(
  event: MarketDeployedCreate
): void {
  let id = event.params.market.toHexString()

  let entity = new Market(id)
  entity.marketAddress = event.params.market
  entity.index = event.params.index
  entity.createdAtBlock = event.block.number
  entity.createdAtTimestamp = event.block.timestamp

  entity.save()
}

export function handleMarketDeployedCreate2(
  event: MarketDeployedCreate2
): void {
  let id = event.params.market.toHexString()

  let entity = new Create2Market(id)
  entity.marketAddress = event.params.market
  entity.salt = event.params.salt
  entity.index = event.params.index
  entity.createdAtBlock = event.block.number
  entity.createdAtTimestamp = event.block.timestamp

  entity.save()
}

export function handleProposalCreated(
  event: ProposalCreated
): void {
  let id = event.params.proposalId.toString()

  let entity = new Proposal(id)
  entity.proposer = event.params.proposer
  entity.description = event.params.description
  entity.createdAtBlock = event.block.number
  entity.createdAtTimestamp = event.block.timestamp

  entity.save()
}

export function handleVoteCast(
  event: VoteCast
): void {
  let id =
    event.params.proposalId.toString() +
    "-" +
    event.params.voter.toHexString()

  let entity = new Vote(id)
  entity.proposalId = event.params.proposalId
  entity.voter = event.params.voter
  entity.support = event.params.support
  entity.weight = event.params.weight
  entity.reason = event.params.reason
  entity.createdAtBlock = event.block.number
  entity.createdAtTimestamp = event.block.timestamp

  entity.save()
}

export function handleFeesReceived(
  event: FeesReceived
): void {
  let id =
    event.transaction.hash.toHexString() +
    "-" +
    event.logIndex.toString()

  let entity = new VaultFee(id)
  entity.from = event.params.from
  entity.assets = event.params.assets
  entity.createdAtBlock = event.block.number
  entity.createdAtTimestamp = event.block.timestamp

  entity.save()
}