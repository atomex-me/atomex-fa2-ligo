type txParam is list (address * (nat * nat));
type transferParam is list (address * txParam);

type initiateParam is record [
    hashedSecret: bytes;
    participant: address;
    refundTime: timestamp;
    tokenAddress: address;
    tokenId: nat;
    totalAmount: nat;
    payoffAmount: nat;
]

type parameter is 
  | Initiate of initiateParam
  | Redeem of bytes
  | Refund of bytes

type swapState is record [
    initiator: address;
    participant: address;
    refundTime: timestamp;
    tokenAddress: address;
    tokenId: nat;
    totalAmount: nat;
    payoffAmount: nat;
]

type storage is big_map(bytes, swapState);

[@inline] function getSwapState(const hashedSecret: bytes; const s: storage) : swapState is
  case s[hashedSecret] of [
    | Some(state) -> state
    | None -> (failwith("no swap for such hash") : swapState)
  ];

[@inline] function getTransferEntry(const tokenAddress: address) : contract(transferParam) is
  case (Tezos.get_entrypoint_opt("%transfer", tokenAddress) : option(contract(transferParam))) of [
    | Some(entry) -> entry
    | None -> (failwith("expected transfer entrypoint") : contract(transferParam))
  ];

[@inline] function transfer(const transferEntry: contract(transferParam); 
                  const id: nat;
                  const src: address;
                  const dst: address; 
                  const value: nat) : operation is
  block {
    const params: transferParam = list[(src, list[(dst, (id, value))])];
    const op: operation = Tezos.transaction(params, 0tz, transferEntry);
  } with op;

[@inline] function transferPayoff(
    const transferEntry: contract(transferParam); 
    const id: nat; 
    const payoffAmount: nat
) : list(operation) is
  block {
    const hasPayoff: bool = payoffAmount > 0n;
  } with case hasPayoff of [
    | True -> list[transfer(transferEntry, id, Tezos.get_self_address(), Tezos.get_sender(), payoffAmount)]
    | False -> (nil : list(operation))
  ];

function doInitiate(const initiate: initiateParam; var s: storage) : (list(operation) * storage) is 
  block {
    if (initiate.payoffAmount > initiate.totalAmount) then failwith("payoff amount exceeds the total") else skip;
    if (initiate.refundTime <= Tezos.get_now()) then failwith("refund time has already come") else skip;
    if (32n =/= Bytes.length(initiate.hashedSecret)) then failwith("hash size doesn't equal 32 bytes") else skip;
    if (Tezos.get_source() = initiate.participant) then failwith("SOURCE cannot act as participant") else skip;
    if (Tezos.get_sender() = initiate.participant) then failwith("SENDER cannot act as participant") else skip;

    const state: swapState = 
      record [
        initiator = Tezos.get_sender();
        participant = initiate.participant;
        refundTime = initiate.refundTime;
        tokenAddress = initiate.tokenAddress;
        tokenId = initiate.tokenId;
        totalAmount = initiate.totalAmount;
        payoffAmount = initiate.payoffAmount;
      ];

    case s[initiate.hashedSecret] of [
      | None -> s[initiate.hashedSecret] := state
      | _ -> failwith("swap for this hash is already initiated")
    ];

    const transferEntry: contract(transferParam) = getTransferEntry(initiate.tokenAddress);
    const depositTx: operation = transfer(
      transferEntry, initiate.tokenId, Tezos.get_sender(), Tezos.get_self_address(), initiate.totalAmount);
  } with (list[depositTx], s)

function doRedeem(const secret: bytes; var s: storage) : (list(operation) * storage) is
  block {
    if (32n =/= Bytes.length(secret)) then failwith("secret size doesn't equal 32 bytes") else skip;
    const hashedSecret: bytes = Crypto.sha256(Crypto.sha256(secret));
    const swap: swapState = getSwapState(hashedSecret, s);
    if (Tezos.get_now() >= swap.refundTime) then failwith("refund time has already come") else skip;

    remove hashedSecret from map s;

    const transferEntry: contract(transferParam) = getTransferEntry(swap.tokenAddress);
    const redeemAmount: nat = abs(swap.totalAmount - swap.payoffAmount);
    const redeemOperation: operation = transfer(transferEntry, swap.tokenId, Tezos.get_self_address(), swap.participant, redeemAmount);
    const payoffOperations: list(operation) = transferPayoff(transferEntry, swap.tokenId, swap.payoffAmount);
  } with (redeemOperation # payoffOperations, s) 

function doRefund(const hashedSecret: bytes; var s: storage) : (list(operation) * storage) is
  block {
    const swap: swapState = getSwapState(hashedSecret, s);
    if (Tezos.get_now() < swap.refundTime) then failwith("refund time hasn't come") else skip;

    remove hashedSecret from map s;

    const transferEntry: contract(transferParam) = getTransferEntry(swap.tokenAddress);
    const refundTx: operation = transfer(transferEntry, swap.tokenId, Tezos.get_self_address(), swap.initiator, swap.totalAmount);
  } with (list[refundTx], s) 

function main (const p: parameter; var s: storage) : (list(operation) * storage) is
block {
  if 0tz =/= Tezos.get_amount() then failwith("this contract does not accept tez") else skip;
} with case p of [
  | Initiate(initiate) -> (doInitiate(initiate, s))
  | Redeem(redeem) -> (doRedeem(redeem, s))
  | Refund(refund) -> (doRefund(refund, s))
]