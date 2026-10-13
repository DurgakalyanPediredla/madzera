

export default function Home() {
  return (
    <main className="flex min-h-screen bg-slate-50">
      <section className="hidden w-1/2 flex-col justify-between bg-slate-950 p-12 text-white lg:flex">
        <div className="text-2xl font-bold tracking-tight">
          MADZERA<span className="text-cyan-400">.</span>
        </div>

        <div>
          <p className="mb-4 text-sm font-semibold uppercase tracking-widest text-cyan-400">
            Operational assurance
          </p>
          <h1 className="max-w-lg text-5xl font-semibold leading-tight">
            Clarity and control for customs operations.
          </h1>
          <p className="mt-6 max-w-md text-lg text-slate-300">
            A secure workspace for managing customer enquiries,
            operational cases and accountability.
          </p>
        </div>

        <p className="text-sm text-slate-400">
          Madzera — Built for customs intermediaries
        </p>
      </section>

      <section className="flex w-full items-center justify-center px-6 py-12 lg:w-1/2">
        <div className="w-full max-w-sm">
          <div className="mb-10 text-2xl font-bold text-slate-950 lg:hidden">
            MADZERA.
          </div>

          <p className="mb-2 text-sm font-semibold text-cyan-700">
            EMPLOYEE PORTAL
          </p>

          <h2 className="text-3xl font-semibold tracking-tight text-slate-950">
            Welcome back
          </h2>

          <p className="mt-3 text-sm text-slate-600">
            Sign in to access your organisation&apos;s workspace.
          </p>

          <form className="mt-8 space-y-5">
            <div>
              <label
                htmlFor="email"
                className="mb-2 block text-sm font-medium text-slate-700"
              >
                Work email
              </label>
              <input
                id="email"
                type="email"
                autoComplete="email"
                placeholder="name@company.com"
                required
                className="w-full rounded-lg border border-slate-300 bg-white px-4 py-3 text-slate-950 outline-none focus:border-cyan-600 focus:ring-2 focus:ring-cyan-100"
              />
            </div>

            <div>
              <label
                htmlFor="password"
                className="mb-2 block text-sm font-medium text-slate-700"
              >
                Password
              </label>
              <input
                id="password"
                type="password"
                autoComplete="current-password"
                placeholder="Enter your password"
                required
                className="w-full rounded-lg border border-slate-300 bg-white px-4 py-3 text-slate-950 outline-none focus:border-cyan-600 focus:ring-2 focus:ring-cyan-100"
              />
            </div>

            <button
              type="button"
              disabled
              className="w-full cursor-not-allowed rounded-lg bg-slate-800 px-4 py-3 font-semibold text-white opacity-70"
            >
              Sign in — coming soon
            </button>
          </form>

          <p className="mt-8 text-center text-xs text-slate-500">
            Access is restricted to authorised employees.
          </p>

          <p className="mt-4 text-center text-xs text-slate-400">
            Authentication integration is not yet enabled.
          </p>
        </div>
      </section>
    </main>
  );
}
