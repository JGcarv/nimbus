# Nimbus
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed except according to those terms.


import
  strformat, times, options,
  eth/[common, rlp],
  ../validation, ./difficulty, ../vm/interpreter/vm_forks, ../constants

export BlockHeader

proc hasUncles*(header: BlockHeader): bool = header.ommersHash != EMPTY_UNCLE_HASH

proc `$`*(header: BlockHeader): string =
  result = &"BlockHeader(timestamp: {header.timestamp} difficulty: {header.difficulty} blockNumber: {header.blockNumber} gasLimit: {header.gasLimit})"

proc gasLimitBounds*(parent: BlockHeader): (Uint256, Uint256) =
  ## Compute the boundaries for the block gas limit based on the parent block.
  let
    gasLimit = parent.gasLimit.u256
    boundaryRange = (parent.gasLimit div GAS_LIMIT_ADJUSTMENT_FACTOR).u256
    upperBound = gasLimit + boundaryRange
    lowerBound = max(GAS_LIMIT_MINIMUM.u256, gasLimit - boundaryRange)

  return (lowerBound, upperBound)

proc computeGasLimit*(parent: BlockHeader, gasLimitFloor: GasInt): GasInt =
  #[
    For each block:
    - decrease by 1/1024th of the gas limit from the previous block
    - increase by 50% of the total gas used by the previous block
    If the value is less than the given `gas_limit_floor`:
    - increase the gas limit by 1/1024th of the gas limit from the previous block.
    If the value is less than the GAS_LIMIT_MINIMUM:
    - use the GAS_LIMIT_MINIMUM as the new gas limit.
  ]#
  if gasLimitFloor < GAS_LIMIT_MINIMUM:
      raise newException(ValueError,
          &"""
          The `gasLimitFloor` value must be greater than the GAS_LIMIT_MINIMUM.
          Got {gasLimitFloor}. Must be greater than {GAS_LIMIT_MINIMUM}
          """
      )

  let decay = parent.gasLimit div GAS_LIMIT_EMA_DENOMINATOR
  var usageIncrease: GasInt

  if parent.gasUsed > 0:
      usageIncrease = (
          parent.gas_used * GAS_LIMIT_USAGE_ADJUSTMENT_NUMERATOR
      ) div GAS_LIMIT_USAGE_ADJUSTMENT_DENOMINATOR div GAS_LIMIT_EMA_DENOMINATOR

  let gasLimit = max(
      GAS_LIMIT_MINIMUM,
      parent.gasLimit - decay + usage_increase
  )

  if gas_limit < GAS_LIMIT_MINIMUM:
      return GAS_LIMIT_MINIMUM
  elif gas_limit < gasLimitFloor:
      return parent.gas_limit + decay
  else:
      return gas_limit

proc generateHeaderFromParentHeader*(parent: BlockHeader,
    coinbase: EthAddress, fork: Fork, timestamp: Option[EthTime],
    extraData: Blob): BlockHeader =

  var lcTimestamp: EthTime
  if timestamp.isNone:
    lcTimeStamp = max(getTime(), parent.timestamp + 1.milliseconds)  # Note: Py-evm uses +1 second, not ms
  else:
    lcTimestamp = timestamp.get()

  if lcTimestamp <= parent.timestamp:
    raise newException(ValueError, "header.timestamp should be higher than parent.timestamp")

  result = BlockHeader(
    timestamp: lcTimestamp,
    blockNumber: (parent.blockNumber + 1),
    difficulty: calcDifficulty(lcTimestamp, parent, fork),
    gasLimit: computeGasLimit(parent, gasLimitFloor = GENESIS_GAS_LIMIT),
    stateRoot: parent.stateRoot,
    coinbase: coinbase,
    extraData: extraData,
  )
