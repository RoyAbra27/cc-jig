import axios from 'axios';

const client = axios.create({ baseURL: process.env.BILLING_URL, timeout: 5000 });

export async function fetchInvoices(customerId: string) {
  const res = await client.get(`/customers/${customerId}/invoices`);
  return res.data;
}
