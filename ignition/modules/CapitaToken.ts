import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import { network } from "hardhat";
import { Router, routerAddresses } from "../../config";

export default buildModule("CapitaToken", (m) => {
  const net = network.name as Router;
  const router = routerAddresses[net];
  console.log({ net, router });
  const capitaToken = m.contract("CapitaToken", [
    "CapitaToken",
    "CPT",
    18,
    router,
  ]);

  m.call(capitaToken, "updateTradingParams", [true, 3, 10, 1, true]);

  m.call(capitaToken, "updateWallets", [
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
    "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
    "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65",
  ]);

  return { capitaToken };
});
