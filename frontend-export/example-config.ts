import { sepolia } from 'viem/chains'

import addresses from './sepolia-demo.example.json'

export const liberlandSepolia = {
  chain: sepolia,
  chainId: 11155111,
  explorer: 'https://sepolia.etherscan.io',
  addresses,
} as const

export type LiberlandSepoliaAddresses = typeof addresses
