"use client";

import { ReactNode, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";

type AuthGuardProps = {
  children: ReactNode;
};

export default function AuthGuard({ children }: AuthGuardProps) {
  const router = useRouter();
  const [authenticated, setAuthenticated] = useState(false);

  useEffect(() => {
    let active = true;

    async function checkSession() {
      const { data, error } = await supabase.auth.getUser();

      if (!active) return;

      if (error || !data.user) {
        setAuthenticated(false);
        router.replace("/login");
      } else {
        setAuthenticated(true);
      }
    }

    void checkSession();

    const { data: listener } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        if (!active) return;

        if (!session) {
          setAuthenticated(false);
          router.replace("/login");
        }
      }
    );

    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, [router]);

  if (!authenticated) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#FAF9F6] text-sm text-[#756B60]">
        Verifying employee session...
      </main>
    );
  }

  return <>{children}</>;
}
