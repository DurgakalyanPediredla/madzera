"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";

export default function LoginPage() {
  const router = useRouter();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function handleLogin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setLoading(true);

    try {
      const { error: loginError } =
        await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        });

      if (loginError) {
        setError(loginError.message);
        return;
      }

      router.replace("/cases");
    } catch {
      setError("Unable to connect. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#FAF9F6] px-4 text-[#39352F]">
      <section className="w-full max-w-md rounded-xl border border-[#D8CBB8] bg-white p-8 shadow-sm">
        <h1 className="text-2xl font-semibold">Madzera</h1>

        <p className="mt-2 text-sm text-[#756B60]">
          Employee operations workspace
        </p>

        <h2 className="mt-8 text-lg font-semibold">
          Sign in
        </h2>

        <form onSubmit={handleLogin} className="mt-5 space-y-5">
          <div>
            <label
              htmlFor="email"
              className="block text-sm font-medium"
            >
              Work email
            </label>

            <input
              id="email"
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              className="mt-2 w-full rounded-md border border-[#D8CBB8] px-3 py-2"
            />
          </div>

          <div>
            <label
              htmlFor="password"
              className="block text-sm font-medium"
            >
              Password
            </label>

            <input
              id="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              className="mt-2 w-full rounded-md border border-[#D8CBB8] px-3 py-2"
            />
          </div>

          {error && (
            <p role="alert" className="text-sm text-red-700">
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-md bg-[#51483F] px-4 py-3 text-sm font-medium text-white disabled:opacity-50"
          >
            {loading ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </section>
    </main>
  );
}
