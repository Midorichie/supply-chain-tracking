import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.5.4/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
  name: "Ensure that stakeholders can register themselves",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const manufacturer = accounts.get("wallet_1")!;
    
    let block = chain.mineBlock([
      Tx.contractCall(
        "supply-chain",
        "register-stakeholder",
        [types.ascii("ACME Manufacturing"), types.ascii("manufacturer")],
        manufacturer.address
      )
    ]);
    
    // Assert transaction success
    assertEquals(block.receipts.length, 1);
    assertEquals(block.height, 2);
    assertEquals(block.receipts[0].result.expectOk(), manufacturer.address);
  },
});

Clarinet.test({
  name: "Ensure that contract owner can verify stakeholders",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const manufacturer = accounts.get("wallet_1")!;
    
    // First register the stakeholder
    let registerBlock = chain.mineBlock([
      Tx.contractCall(
        "supply-chain",
        "register-stakeholder",
        [types.ascii("ACME Manufacturing"), types.ascii("manufacturer")],
        manufacturer.address
      )
    ]);
    
    // Then verify the stakeholder
    let verifyBlock = chain.mineBlock([
      Tx.contractCall(
        "supply-chain",
        "verify-stakeholder",
        [types.principal(manufacturer.address)],
        deployer.address
      )
    ]);
    
    // Assert verification transaction success
    assertEquals(verifyBlock.receipts.length, 1);
    assertEquals(verifyBlock.height, 3);
    assertEquals(verifyBlock.receipts[0].result.expectOk(), manufacturer.address);
  },
});

Clarinet.test({
  name: "Ensure that manufacturers can create products",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const manufacturer = accounts.get("wallet_1")!;
    
    // Register and verify manufacturer
    chain.mineBlock([
      Tx.contractCall(
        "supply-chain",
        "register-stakeholder",
        [types.ascii("ACME Manufacturing"), types.ascii("manufacturer")],
        manufacturer.address
      ),
      Tx.contractCall(
        "supply-chain",
        "verify-stakeholder",
        [types.principal(manufacturer.address)],
        deployer.address
      )
    ]);
    
    // Create a product
    const productId = "0x0102030405060708091011121314151617181920212223242526272829303132";
    let block = chain.mineBlock([
      Tx.contractCall(
        "supply-chain",
        "create-product",
        [types.buff(productId), types.ascii("Organic Coffee Beans")],
        manufacturer.address
      )
    ]);
    
    // Assert product creation success
    assertEquals(block.receipts.length, 1);
    assertEquals(block.receipts[0].result.expectOk(), types.buff(productId));
  },
});

Clarinet.test({
  name: "Ensure custody transfer works correctly",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const manufacturer = accounts.get("wallet_1")!;
    const distributor = accounts.get("wallet_2")!;
    
    // Setup - register and verify stakeholders
    chain.mineBlock([
      Tx.contractCall(
        "supply-chain",
        "register-stakeholder",
        [types.ascii("ACME Manufacturing"), types.ascii("manufacturer")],
        manufacturer.address
      ),
      Tx.contractCall(
        "supply-chain",
        "verify-stakeholder",
        [types.principal(manufacturer.address)],
        deployer.address
      ),
      Tx.contractCall(
        "supply-chain",
        "register-stakeholder",
        [types.ascii("Global Distribution"), types.ascii("distributor")],
        distributor.address
      ),
      Tx.contractCall(
        "supply-chain",
        "verify-stakeholder",
        [types.principal(distributor.address)],
        deployer.address
      )
    ]);
    
    // Create a product
    const productId = "0x0102030405060708091011121314151617181920212223242526272829303132";
    chain.mineBlock([
      Tx.contractCall(
        "supply-chain",
        "create-product",
        [types.buff(productId), types.ascii("Organic Coffee Beans")],
        manufacturer.address
      )
    ]);
    
    // Transfer custody to distributor
    let block = chain.mineBlock([
      Tx.contractCall(
        "supply-chain",
        "transfer-custody",
        [
          types.buff(productId), 
          types.principal(distributor.address),
          types.some(types.tuple({ lat: types.int(4000000), lng: types.int(-7300000) })),
          types.some(types.ascii("Shipped via express freight"))
        ],
        manufacturer.address
      )
    ]);
    
    // Assert transfer success
    assertEquals(block.receipts.length, 1);
    assertEquals(block.receipts[0].result.expectOk(), types.uint(2));
  },
});
