import {expect} from "chai"
import {ethers, userConfig} from "hardhat"
import {BigNumber} from "ethers"
import {TypedDataUtils} from "ethers-eip712"
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers"
import {
    Governance,
    MarketplaceBase,
    ERC20Test,
    TokenCreator,
    Collectible1155,
    NFTFactory1155,
} from "../typechain"
import {types} from "hardhat/config"
import {parseBytes32String, toUtf8Bytes} from "ethers/lib/utils"
import {AnyTuple} from "@polkadot/types-codec/types"

const typedData = {
    types: {
        EIP712Domain: [
            {name: "name", type: "string"},
            {name: "version", type: "string"},
            {name: "chainId", type: "uint256"},
            {name: "verifyingContract", type: "address"},
        ],
        User: [
            {name: "addr", type: "address"},
            {name: "v", type: "uint8"},
            {name: "deadline", type: "uint256"},
            {name: "r", type: "bytes32"},
            {name: "s", type: "bytes32"},
        ],
        Header: [
            {name: "buyer", type: "User"},
            {name: "seller", type: "User"},
            {name: "nftContract", type: "address"},
            {name: "paymentToken", type: "address"},
        ],
        Item: [
            {name: "amount", type: "uint256"},
            {name: "tokenId", type: "uint256"},
            {name: "unitPrice", type: "uint256"},
            {name: "tokenURI", type: "string"},
        ],
        Bulk: [
            {name: "amounts", type: "uint256[]"},
            {name: "tokenIds", type: "uint256[]"},
            {name: "unitPrices", type: "uint256[]"},
            {name: "tokenURIs", type: "string[]"},
        ],
        Receipt: [
            {name: "header", type: "Header"},
            {name: "item", type: "Item"},
            {name: "nonce", type: "uint256"},
            {name: "deadline", type: "uint256"},
        ],
        BulkReceipt: [
            {name: "header", type: "Header"},
            {name: "bulk", type: "Bulk"},
            {name: "nonce", type: "uint256"},
            {name: "deadline", type: "uint256"},
        ],
    },
    domain: {
        name: "Marketplace",
        version: "1",
        chainId: 31337,
        verifyingContract: "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
    },
    primaryType: "Receipt" as const,
    message: {
        header: {
            buyer: {
                addr: "",
                v: BigNumber.from(0),
                deadline: BigNumber.from(0),
                r: "",
                s: "",
            },
            seller: {
                addr: "",
                v: BigNumber.from(0),
                deadline: BigNumber.from(0),
                r: "",
                s: "",
            },
            nftContract: "",
            paymentToken: "",
        },
        item: {
            amount: BigNumber.from(0),
            tokenId: BigNumber.from(0),
            unitPrice: BigNumber.from(0),
            tokenURI: "",
        },
        nonce: BigNumber.from(0),
        deadline: BigNumber.from(0),
    },
}

async function increaseTime(duration: number): Promise<void> {
    ethers.provider.send("evm_increaseTime", [duration])
    ethers.provider.send("evm_mine", [])
}

async function decreaseTime(duration: number): Promise<void> {
    ethers.provider.send("evm_increaseTime", [duration * -1])
    ethers.provider.send("evm_mine", [])
}

async function signReceipt(
    addrBuyer: string,
    vBuyer: BigNumber,
    deadlineBuyer: BigNumber,
    rBuyer: string,
    sBuyer: string,
    addrSeller: string,
    vSeller: BigNumber,
    deadlineSeller: BigNumber,
    rSeller: string,
    sSeller: string,
    nftContract: string,
    paymentToken: string,
    amount: BigNumber,
    tokenId: BigNumber,
    unitPrice: BigNumber,
    tokenURI: string,
    nonce: BigNumber,
    deadline: BigNumber,
    verifyingContract: string,
    verifier: SignerWithAddress
): Promise<[any, string]> {
    let message = Object.assign({}, typedData.message)
    message.header = {
        buyer: {
            addr: addrBuyer,
            v: vBuyer,
            deadline: deadlineBuyer,
            r: rBuyer,
            s: sBuyer,
        },
        seller: {
            addr: addrSeller,
            v: vSeller,
            deadline: deadlineSeller,
            r: rSeller,
            s: sSeller,
        },
        nftContract: nftContract,
        paymentToken: paymentToken,
    }
    message.item = {
        amount: amount,
        tokenId: tokenId,
        unitPrice: unitPrice,
        tokenURI: tokenURI,
    }
    message.nonce = nonce
    message.deadline = deadline
    let typedData_ = JSON.parse(JSON.stringify(typedData))
    typedData_.message = message
    typedData_.domain.verifyingContract = verifyingContract
    const digest = TypedDataUtils.encodeDigest(typedData_)
    console.log(`digestHex: ${ethers.utils.hexlify(digest)}`)
    const receiptHash = TypedDataUtils.hashStruct(
        typedData_,
        "Receipt",
        typedData_.message
    )
    console.log("receipt ts", ethers.utils.hexlify(receiptHash))
    return [message, await verifier.signMessage(digest)]
}

async function buyerSign(
    buyer: SignerWithAddress,
    owner: string,
    spender: string,
    value: BigNumber,
    nonce: BigNumber,
    deadline: BigNumber
): Promise<[string, string, number]> {
    const message = ethers.utils.solidityKeccak256(
        ["address", "address", "uint256", "uint256", "uint256"],
        [owner, spender, value, nonce, deadline]
    )
    const signature = await buyer.signMessage(ethers.utils.arrayify(message))
    const {r, s, v} = ethers.utils.splitSignature(signature)
    return [r, s, v]
}

async function sellerSign(
    seller: SignerWithAddress,
    owner: string,
    spender: string,
    nonce: BigNumber,
    deadline: BigNumber
): Promise<[string, string, number]> {
    const message = ethers.utils.solidityKeccak256(
        ["address", "address", "uint256", "uint256"],
        [owner, spender, nonce, deadline]
    )
    const signature = await seller.signMessage(ethers.utils.arrayify(message))
    const {r, s, v} = ethers.utils.splitSignature(signature)
    return [r, s, v]
}

describe("MarketplaceBase", () => {
    let admin: SignerWithAddress
    let users: SignerWithAddress[]
    let manager: SignerWithAddress
    let verifier: SignerWithAddress
    let treasury: SignerWithAddress

    let governance: Governance
    let paymentToken: ERC20Test
    let nftFactory1155: NFTFactory1155
    let cloneNft1155: Collectible1155
    let marketplace: MarketplaceBase
    let tokenCreator: TokenCreator
    let serviceFee: number
    const balance = 1e5
    const tokenURI = "https://triton.com/token"

    beforeEach(async () => {
        ;[admin, manager, verifier, treasury, ...users] =
            await ethers.getSigners()

        const ERC20TestFactory = await ethers.getContractFactory(
            "ERC20Test",
            admin
        )
        paymentToken = await ERC20TestFactory.deploy("PaymentToken", "PMT")
        await paymentToken.deployed()
        for (const u of users) await paymentToken.mint(u.address, balance)

        const GovernanceFactory = await ethers.getContractFactory(
            "Governance",
            admin
        )
        governance = await GovernanceFactory.deploy(
            manager.address,
            treasury.address,
            verifier.address
        )
        await governance.deployed()
        await governance.connect(manager).registerToken(paymentToken.address)

        const NFTFactory1155Factory = await ethers.getContractFactory(
            "NFTFactory1155",
            admin
        )
        nftFactory1155 = await NFTFactory1155Factory.deploy(governance.address)
        await nftFactory1155.deployed()

        await nftFactory1155.deployCollectible("Triton", "TNT", "")
        const version = ethers.utils.keccak256(
            ethers.utils.toUtf8Bytes("NFTFactory1155_v1")
        )
        const salt = ethers.utils.keccak256(
            ethers.utils.solidityPack(
                ["bytes32", "string", "string", "string"],
                [version, "Triton", "TNT", ""]
            )
        )
        const cloneNft1155Address = await nftFactory1155.deployedContracts(
            BigNumber.from(salt)
        )
        cloneNft1155 = await ethers.getContractAt(
            "Collectible1155",
            cloneNft1155Address,
            admin
        )

        serviceFee = 250
        const MarketplaceBaseFactory = await ethers.getContractFactory(
            "MarketplaceBase",
            admin
        )
        marketplace = await MarketplaceBaseFactory.deploy(
            governance.address,
            serviceFee,
            500
        )
        await marketplace.deployed()
        await governance.connect(manager).updateMarketplace(marketplace.address)

        const TokenCreatorFactory = await ethers.getContractFactory(
            "TokenCreator",
            admin
        )
        tokenCreator = await TokenCreatorFactory.deploy()
        await tokenCreator.deployed()
    })

    it("should let user redeem with valid receipt", async () => {
        const now = (await ethers.provider.getBlock("latest")).timestamp
        let buyer: SignerWithAddress
        let creator: SignerWithAddress
        buyer = users[0]
        creator = users[1]
        const nonce = await marketplace.nonces(marketplace.address)
        const creatorFee = 250
        const tokenId = await tokenCreator.createTokenId(
            creatorFee,
            1155,
            2e5,
            0,
            creator.address
        )
        let amount = 12
        let unitPrice = 500
        const totalPay = amount * unitPrice
        const deadline = now + 60 * 1000
        let receipt: any
        let signature: string

        //Buyer sign signature to permit marketplace to use totalPay to buy nft
        const buyerNonce = await marketplace.nonces(buyer.address)
        let rBuyer: string
        let sBuyer: string
        let vBuyer: number
        ;[rBuyer, sBuyer, vBuyer] = await buyerSign(
            buyer,
            buyer.address,
            marketplace.address,
            BigNumber.from(totalPay),
            BigNumber.from(buyerNonce),
            BigNumber.from(deadline)
        )

        //Seller sign signature to permit marketplace to transfer nft when buyer buy nft
        let rSeller: string
        let sSeller: string
        let vSeller: number
        const sellerNonce = await marketplace.nonces(creator.address)
        ;[rSeller, sSeller, vSeller] = await sellerSign(
            creator,
            creator.address,
            marketplace.address,
            BigNumber.from(sellerNonce),
            BigNumber.from(deadline)
        )
        ;[receipt, signature] = await signReceipt(
            buyer.address,
            BigNumber.from(vBuyer),
            BigNumber.from(deadline),
            rBuyer,
            sBuyer,
            creator.address,
            BigNumber.from(vSeller),
            BigNumber.from(deadline),
            rSeller,
            sSeller,
            cloneNft1155.address,
            paymentToken.address,
            BigNumber.from(amount),
            BigNumber.from(tokenId),
            BigNumber.from(unitPrice),
            tokenURI,
            nonce,
            BigNumber.from(deadline),
            marketplace.address,
            verifier
        )

        console.log(`signature: ${signature}`)
        console.log(`verifier address: ${verifier.address}`)
        // const enodeType2 = TypedDataUtils.encodeType(
        //     typedData.types,
        //     "BulkReceipt"
        // )
        // console.log(enodeType2)
        // console.log(
        //     ethers.utils.keccak256(ethers.utils.toUtf8Bytes(enodeType2))
        // )

        console.log("----------------------------------------------------")
        console.log(totalPay)
        await paymentToken.connect(buyer).approve(marketplace.address, totalPay)
        const tx = await marketplace
            .connect(buyer)
            .redeem(receipt, signature, {value: totalPay})
        console.log(tx)
    })
})
