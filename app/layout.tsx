import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'AegisMezo V2 | Omni-Clearing & Boost Engine on Mezo',
  description:
    'Redemption-Shielded Self-Healing Troves, veBTC x veMEZO 5x Boost Matching Market, MUSD Positive-Carry Router, and x402 Cross-Chain Float Clearing on Mezo (31611).',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
