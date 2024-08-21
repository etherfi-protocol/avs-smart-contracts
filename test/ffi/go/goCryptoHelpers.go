package main

import (
	"fmt"
	"log"
	"math/big"
	"os"
	"strings"

	"github.com/consensys/gnark-crypto/ecc/bn254"
	"github.com/ethereum/go-ethereum/crypto"
)

func main() {

	// switch for selecting helper function to call
	switch os.Args[1] {
	case "computeG2Point":
		computeG2Point()
	case "getECDSAPubKey":
		getECDSAPubKey()
	}

}

// gets the ECDSA public key from the private key
func getECDSAPubKey() {
	// int string
	arg1 := os.Args[2]

	// Convert input integer string to *big.Int
	privInt, success := new(big.Int).SetString(arg1, 10)
	if !success {
		log.Fatalf("Failed to parse integer string: %s", arg1)
	}

	// Convert to 32-byte slice for `ToECDSA` input
	privBytes := privInt.Bytes()
	if len(privBytes) < 32 {
		// Pad the byte slice with leading zeros if necessary
		paddedBytes := make([]byte, 32)
		copy(paddedBytes[32-len(privBytes):], privBytes)
		privBytes = paddedBytes
	} else if len(privBytes) > 32 {
		log.Fatalf("Integer is too large. It must be exactly 256 bits.")
	}

	privateKey, err := crypto.ToECDSA(privBytes)
	if err != nil {
		log.Fatalf("Failed to create ECDSA private key: %v", err)
	}

	// Get X and Y coordinates
	x, y := privateKey.PublicKey.X, privateKey.PublicKey.Y
	// Convert X and Y to 32-byte big-endian format
	xBytes := x.Bytes()
	yBytes := y.Bytes()

	switch os.Args[3] {
	case "X":
		fmt.Printf("%x\n", xBytes)
	case "Y":
		fmt.Printf("%x\n", yBytes)
	}
}

// computes the requested g2 point
func computeG2Point() {
	//parse args
	arg1 := os.Args[2]
	n := new(big.Int)
	n, _ = n.SetString(arg1, 10)

	//g2 mul
	pubkey := new(bn254.G2Affine).ScalarMultiplication(GetG2Generator(), n)
	px := pubkey.X.String()
	py := pubkey.Y.String()

	//parse out point coords to big ints
	pxs := strings.Split(px, "+")
	pxss := strings.Split(pxs[1], "*")

	pys := strings.Split(py, "+")
	pyss := strings.Split(pys[1], "*")

	pxsInt := new(big.Int)
	pxsInt, _ = pxsInt.SetString(pxs[0], 10)

	pxssInt := new(big.Int)
	pxssInt, _ = pxssInt.SetString(pxss[0], 10)

	pysInt := new(big.Int)
	pysInt, _ = pysInt.SetString(pys[0], 10)

	pyssInt := new(big.Int)
	pyssInt, _ = pyssInt.SetString(pyss[0], 10)

	//switch to print coord requested
	switch os.Args[3] {
	case "1":
		fmt.Printf("0x%064X", pxsInt)
	case "2":
		fmt.Printf("0x%064X", pxssInt)
	case "3":
		fmt.Printf("0x%064X", pysInt)
	case "4":
		fmt.Printf("0x%064X", pyssInt)
	}
}

func GetG2Generator() *bn254.G2Affine {
	g2Gen := new(bn254.G2Affine)
	g2Gen.X.SetString("10857046999023057135944570762232829481370756359578518086990519993285655852781",
		"11559732032986387107991004021392285783925812861821192530917403151452391805634")
	g2Gen.Y.SetString("8495653923123431417604973247489272438418190587263600148770280649306958101930",
		"4082367875863433681332203403145435568316851327593401208105741076214120093531")
	return g2Gen
}
