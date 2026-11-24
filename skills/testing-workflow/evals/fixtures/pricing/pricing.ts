export interface Order {
  items: { price: number; qty: number }[];
  discount: number;
  taxRate: number;
}

export function subtotal(o: Order): number {
  return o.items.reduce((sum, i) => sum + i.price * i.qty, 0);
}

export function total(o: Order): number {
  const net = subtotal(o) * (1 - o.discount);
  return Math.round(net * (1 + o.taxRate) * 100) / 100;
}
