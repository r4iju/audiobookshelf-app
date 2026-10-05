import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { AppProviders } from "@/components/app/providers";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "Audiobook Loft", template: "%s · Audiobook Loft" },
  description: "Your self-hosted library, wherever you listen",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = { width: "device-width", initialScale: 1, viewportFit: "cover" };

// Applies the saved theme before first paint so a light-theme user never sees a dark flash.
const themeScript = `try{var s=JSON.parse(localStorage.getItem("abs-web:v1:settings")||"{}");var t=s.theme;if(t==="system"||!t){t=t==="system"&&matchMedia("(prefers-color-scheme: light)").matches?"light":t==="system"?"dark":"dark"}document.documentElement.dataset.theme=t;if(s.reduceMotion)document.documentElement.dataset.reduceMotion="true"}catch(e){}`;

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" data-theme="dark" suppressHydrationWarning>
      <head>
        {/* biome-ignore lint/security/noDangerouslySetInnerHtml: static pre-hydration theme script */}
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body className="bg-bg text-fg antialiased">
        <AppProviders>{children}</AppProviders>
      </body>
    </html>
  );
}
