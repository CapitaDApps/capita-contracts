export type RouterType = {
  base: string;
  sepolia: string;
  local: string;
};

export type FactoryType = RouterType;

export type Router = keyof RouterType;

export type Factory = keyof FactoryType;

export const routerAddresses: RouterType = {
  base: "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24",
  sepolia: "0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3",
  local: "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24",
};

export const factoryAddresses: FactoryType = {
  base: "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6",
  sepolia: "0xF62c03E08ada871A0bEb309762E260a7a6a880E6",
  local: "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6",
};
