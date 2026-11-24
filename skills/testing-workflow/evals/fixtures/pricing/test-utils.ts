import type { Order } from './pricing';

export function makeOrder(overrides: Partial<Order> = {}): Order {
  return { items: [{ price: 50, qty: 1 }], discount: 0, taxRate: 0.17, ...overrides };
}
