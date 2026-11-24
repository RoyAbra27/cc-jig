import { describe, it, expect } from 'vitest';
import { total } from './pricing';
import { makeOrder } from './test-utils';

describe('total', () => {
  it.each([
    [makeOrder(), 58.5],
    [makeOrder({ discount: 0.1 }), 52.65],
    [makeOrder({ items: [{ price: 20, qty: 3 }] }), 70.2],
  ])('total(%o) = %d', (order, expected) => {
    expect(total(order)).toBe(expected);
  });
});
