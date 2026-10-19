
"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { useRouter } from "next/navigation";
import CreateCaseForm from "./CreateCaseForm";

type CaseStatus = "Open" | "In progress" | "Pending customer";
type CaseOrigin = "customer" | "internal";

type QueueCase = {
  id: string;
  customer: string;
  subject: string;
  status: CaseStatus;
  received: string;
  receivedAt: string;
  origin: CaseOrigin;
  lockedBy?: string;
};

type CaseFilters = {
  caseId: string;
  customer: string;
  subject: string;
  status: string;
  dateFrom: string;
  dateTo: string;
  time: string;
};

const emptyFilters: CaseFilters = {
  caseId: "",
  customer: "",
  subject: "",
  status: "",
  dateFrom: "",
  dateTo: "",
  time: "",
};

type QueueRow = {
  case_id: string;
  case_title: string;
  case_status: string;
  customer_id: string | null;
  created_at: string;
  locked_by_name: string | null;
  case_type: string | null;
};

function mapQueueRow(row: QueueRow): QueueCase {
  const date = new Date(row.created_at);

  const status =
    row.case_status === "in_progress"
      ? "In progress"
      : row.case_status === "pending_customer"
        ? "Pending customer"
        : "Open";

  return {
    id: row.case_id,
    customer: row.customer_id
      ? `Customer ${row.customer_id.slice(0, 8)}`
      : "Internal",
    subject: row.case_title,
    status,
    received: date.toLocaleString("en-GB", {
      day: "2-digit",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "Europe/London",
    }),
    receivedAt: row.created_at,
    origin: row.case_type === "internal_case"
      ? "internal"
      : "customer",
    lockedBy: row.locked_by_name ?? undefined,
  };
}
const inputClass =
  "w-full rounded border border-[#D8CBB8] bg-white px-3 py-2 text-sm text-[#39352F]";

export default function CasesWorkspace() {
  const router = useRouter();
  const [showCreateCase, setShowCreateCase] = useState(false);
  const [createdCaseId, setCreatedCaseId] = useState<string | null>(null);
  const [cases, setCases] = useState<QueueCase[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    async function loadCases() {
      const { data, error } = await supabase.rpc("get_case_queue");

      if (!active) return;

      if (error) {
        setLoadError(error.message);
      } else {
        setCases(((data ?? []) as QueueRow[]).map(mapQueueRow));
        setLoadError(null);
      }

      setLoading(false);
    }

    void loadCases();

    function refreshOnFocus() {
      if (document.visibilityState === "visible") {
        void loadCases();
      }
    }

    window.addEventListener("focus", refreshOnFocus);
    document.addEventListener("visibilitychange", refreshOnFocus);

    return () => {
      active = false;
      window.removeEventListener("focus", refreshOnFocus);
      document.removeEventListener("visibilitychange", refreshOnFocus);
    };
  }, []);
  const [activeBasket, setActiveBasket] =
    useState<CaseOrigin>("customer");

  const [showFilters, setShowFilters] = useState(false);

  const [filters, setFilters] = useState<CaseFilters>({
    ...emptyFilters,
  });

  const [appliedFilters, setAppliedFilters] =
    useState<CaseFilters>({
      ...emptyFilters,
    });

  function updateFilter(
    field: keyof CaseFilters,
    value: string
  ) {
    setFilters((previous) => ({
      ...previous,
      [field]: value,
    }));
  }

  function applyFilters() {
    setAppliedFilters({ ...filters });
    setShowFilters(false);
  }

  function clearFilters() {
    setFilters({ ...emptyFilters });
    setAppliedFilters({ ...emptyFilters });
  }

  function changeBasket(basket: CaseOrigin) {
    setActiveBasket(basket);
    setShowFilters(false);
    setFilters({ ...emptyFilters });
    setAppliedFilters({ ...emptyFilters });
  }

  const customerCount = cases.filter(
    (item) => item.origin === "customer"
  ).length;

  const internalCount = cases.filter(
    (item) => item.origin === "internal"
  ).length;

  const filteredCases = cases.filter((caseItem) => {
    if (caseItem.origin !== activeBasket) {
      return false;
    }

    const matchesCaseId = caseItem.id
      .toLowerCase()
      .includes(appliedFilters.caseId.trim().toLowerCase());

    const matchesCustomer = caseItem.customer
      .toLowerCase()
      .includes(appliedFilters.customer.trim().toLowerCase());

    const matchesSubject = caseItem.subject
      .toLowerCase()
      .includes(appliedFilters.subject.trim().toLowerCase());

    const matchesStatus =
      appliedFilters.status === "" ||
      caseItem.status === appliedFilters.status;

    const receivedDate = caseItem.receivedAt.slice(0, 10);
    const receivedHour = Number(
      caseItem.receivedAt.slice(11, 13)
    );

    const matchesDateFrom =
      appliedFilters.dateFrom === "" ||
      receivedDate >= appliedFilters.dateFrom;

    const matchesDateTo =
      appliedFilters.dateTo === "" ||
      receivedDate <= appliedFilters.dateTo;

    const matchesTime =
      appliedFilters.time === "" ||
      (appliedFilters.time === "morning" &&
        receivedHour >= 6 &&
        receivedHour < 12) ||
      (appliedFilters.time === "afternoon" &&
        receivedHour >= 12 &&
        receivedHour < 18) ||
      (appliedFilters.time === "evening" &&
        (receivedHour >= 18 || receivedHour < 6));

    return (
      matchesCaseId &&
      matchesCustomer &&
      matchesSubject &&
      matchesStatus &&
      matchesDateFrom &&
      matchesDateTo &&
      matchesTime
    );
  });

  const basketTitle =
    activeBasket === "customer"
      ? "Customer queries"
      : "Internal cases";

  return (
    <main className="min-h-screen bg-[#FAF9F6] text-[#39352F]">
      {/* Workspace header */}
      <header className="flex items-center justify-between border-b border-[#D8CBB8] bg-[#EAE4D9] px-6 py-3">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-md border border-[#C9BBA7] bg-[#FAF9F6] text-lg font-bold text-[#51483F]">
            N
          </div>

          <div>
            <p className="text-base font-semibold">
              NorthStar Customs
            </p>
            <p className="text-xs text-[#756B60]">
              Operations Workspace
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <span className="rounded-md border border-[#D8CBB8] bg-[#FAF9F6] px-3 py-2 text-sm text-[#51483F]">
            Demo environment
          </span>

          <div className="flex h-9 w-9 items-center justify-center rounded-full bg-[#D8CBB8] text-sm font-semibold">
            SM
          </div>
        </div>
      </header>

      {/* Queue workspace */}
      <div className="mx-auto flex max-w-[1500px] flex-col gap-6 px-6 py-8 lg:min-h-[calc(100vh-76px)] lg:flex-row">
        {/* Left sidebar */}
        <aside
          aria-label="Case queues"
          className="flex w-full shrink-0 flex-col rounded-lg border border-[#D8CBB8] bg-[#F4F0E9] p-4 lg:w-60"
        >
          <p className="mb-3 text-xs font-semibold uppercase tracking-wide text-[#756B60]">
            Work queues
          </p>

          <nav
            className="space-y-2"
            aria-label="Case origin"
          >
            <button
              type="button"
              onClick={() => changeBasket("customer")}
              aria-pressed={activeBasket === "customer"}
              className={`w-full rounded-md px-3 py-3 text-left text-sm ${
                activeBasket === "customer"
                  ? "bg-white font-semibold shadow-sm"
                  : "hover:bg-white/70"
              }`}
            >
              <span className="flex items-center justify-between gap-2">
                <span>Customer queries</span>
                <span className="text-xs text-[#756B60]">
                  {customerCount}
                </span>
              </span>
            </button>

            <button
              type="button"
              onClick={() => changeBasket("internal")}
              aria-pressed={activeBasket === "internal"}
              className={`w-full rounded-md px-3 py-3 text-left text-sm ${
                activeBasket === "internal"
                  ? "bg-white font-semibold shadow-sm"
                  : "hover:bg-white/70"
              }`}
            >
              <span className="flex items-center justify-between gap-2">
                <span>Internal cases</span>
                <span className="text-xs text-[#756B60]">
                  {internalCount}
                </span>
              </span>
            </button>
          </nav>

          {/* Team selector at bottom of sidebar */}
          <div className="mt-8 border-t border-[#D8CBB8] pt-4 lg:mt-auto">
            <label
              htmlFor="active-team"
              className="mb-2 block text-xs font-medium text-[#756B60]"
            >
              Active team
            </label>

            <select
              id="active-team"
              defaultValue="customs-operations"
              disabled
              title="Team switching will be enabled after authentication and permissions are connected"
              className="w-full rounded border border-[#D8CBB8] bg-white px-2 py-2 text-sm text-[#39352F] disabled:cursor-not-allowed"
            >
              <option value="customs-operations">
                Customs Operations
              </option>
              <option value="customer-services">
                Customer Services
              </option>
              <option value="compliance">
                Compliance
              </option>
            </select>
          </div>
        </aside>

        {/* Right-hand queue */}
        <div className="min-w-0 flex-1">
          <div className="mb-6">
            <div className="flex items-center justify-between gap-4">
              <h1 className="text-2xl font-semibold">
                {basketTitle}
              </h1>
              <button
                type="button"
                onClick={() => {
                  setCreatedCaseId(null);
                  setShowCreateCase((value) => !value);
                }}
                className="rounded-md bg-[#51483F] px-4 py-2 text-sm font-medium text-white hover:bg-[#39352F]"
              >
                {showCreateCase ? "Close form" : "+ Create Case"}
              </button>
            </div>

            <p className="mt-1 text-sm text-[#756B60]">
              {activeBasket === "customer"
                ? "Review and manage customer enquiries."
                : "Review internally raised cases and follow-ups."}
            </p>
          </div>

          {showCreateCase && (
            <div className="mb-6">
              {createdCaseId ? (
                <div className="space-y-4 rounded-lg border border-[#D8CBB8] bg-white p-5">
                  <div className="flex items-center gap-2">
                    <span aria-hidden="true" className="text-green-700">
                      ✓
                    </span>
                    <h2 className="text-lg font-semibold">
                      Case Created Successfully
                    </h2>
                  </div>

                  <p className="text-sm text-[#756B60]">
                    The case has been created and assigned to the selected team.
                  </p>

                  <div className="rounded-md bg-[#F7F4EF] p-4">
                    <p className="mb-1 text-xs text-[#756B60]">Case ID</p>
                    <p className="break-all font-mono text-sm font-medium">
                      {createdCaseId}
                    </p>
                  </div>

                  <div className="flex flex-wrap justify-end gap-3">
                    <button
                      type="button"
                      onClick={() => {
                        setShowCreateCase(false);
                        setCreatedCaseId(null);
                        window.location.reload();
                      }}
                      className="rounded bg-[#51483F] px-4 py-2 text-sm font-medium text-white"
                    >
                      Return to Case Queue
                    </button>

                    <button
                      type="button"
                      onClick={() => router.push(`/cases/${createdCaseId}`)}
                      className="rounded border border-[#D8CBB8] px-4 py-2 text-sm"
                    >
                      Open Case Record
                    </button>
                  </div>
                </div>
              ) : (
                <CreateCaseForm
                  onCancel={() => setShowCreateCase(false)}
                  onCreated={(caseId) => setCreatedCaseId(caseId)}
                />
              )}
            </div>
          )}

          <div className="overflow-hidden rounded-lg border border-[#D8CBB8] bg-white">
            {/* Queue header */}
            <div className="flex items-center justify-between border-b border-[#D8CBB8] px-5 py-3">
              <div>
                <h2 className="text-sm font-semibold">
                  Team queue
                </h2>

                <p className="text-xs text-[#756B60]">
                  {filteredCases.length} cases
                </p>
              </div>

              <button
                type="button"
                onClick={() => setShowFilters(!showFilters)}
                aria-expanded={showFilters}
                aria-controls="case-filters"
                className="rounded-md border border-[#C9BBA7] bg-[#FAF9F6] px-4 py-2 text-sm font-medium text-[#51483F] hover:bg-[#EAE4D9]"
              >
                Filter {showFilters ? "▲" : "▼"}
              </button>
            </div>

            {/* Filters */}
            {showFilters && (
              <div
                id="case-filters"
                className="border-b border-[#D8CBB8] bg-[#FAF9F6] px-5 py-4"
              >
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                  <div>
                    <label
                      htmlFor="filter-case-id"
                      className="mb-1 block text-xs font-medium"
                    >
                      Case ID
                    </label>

                    <input
                      id="filter-case-id"
                      type="text"
                      placeholder="e.g. CASE-1001"
                      value={filters.caseId}
                      onChange={(event) =>
                        updateFilter(
                          "caseId",
                          event.target.value
                        )
                      }
                      className={inputClass}
                    />
                  </div>

                  <div>
                    <label
                      htmlFor="filter-customer"
                      className="mb-1 block text-xs font-medium"
                    >
                      Customer
                    </label>

                    <input
                      id="filter-customer"
                      type="text"
                      placeholder="Customer name"
                      value={filters.customer}
                      onChange={(event) =>
                        updateFilter(
                          "customer",
                          event.target.value
                        )
                      }
                      className={inputClass}
                    />
                  </div>

                  <div>
                    <label
                      htmlFor="filter-subject"
                      className="mb-1 block text-xs font-medium"
                    >
                      Subject
                    </label>

                    <input
                      id="filter-subject"
                      type="text"
                      placeholder="Subject contains..."
                      value={filters.subject}
                      onChange={(event) =>
                        updateFilter(
                          "subject",
                          event.target.value
                        )
                      }
                      className={inputClass}
                    />
                  </div>

                  <div>
                    <label
                      htmlFor="filter-status"
                      className="mb-1 block text-xs font-medium"
                    >
                      Status
                    </label>

                    <select
                      id="filter-status"
                      value={filters.status}
                      onChange={(event) =>
                        updateFilter(
                          "status",
                          event.target.value
                        )
                      }
                      className={inputClass}
                    >
                      <option value="">
                        All statuses
                      </option>
                      <option value="Open">
                        Open
                      </option>
                      <option value="In progress">
                        In progress
                      </option>
                      <option value="Pending customer">
                        Pending customer
                      </option>
                    </select>
                  </div>

                  <div>
                    <label
                      htmlFor="filter-date-from"
                      className="mb-1 block text-xs font-medium"
                    >
                      Received from
                    </label>

                    <input
                      id="filter-date-from"
                      type="date"
                      value={filters.dateFrom}
                      onChange={(event) =>
                        updateFilter(
                          "dateFrom",
                          event.target.value
                        )
                      }
                      className={inputClass}
                    />
                  </div>

                  <div>
                    <label
                      htmlFor="filter-date-to"
                      className="mb-1 block text-xs font-medium"
                    >
                      Received to
                    </label>

                    <input
                      id="filter-date-to"
                      type="date"
                      value={filters.dateTo}
                      onChange={(event) =>
                        updateFilter(
                          "dateTo",
                          event.target.value
                        )
                      }
                      className={inputClass}
                    />
                  </div>

                  <div>
                    <label
                      htmlFor="filter-time"
                      className="mb-1 block text-xs font-medium"
                    >
                      Received time
                    </label>

                    <select
                      id="filter-time"
                      value={filters.time}
                      onChange={(event) =>
                        updateFilter(
                          "time",
                          event.target.value
                        )
                      }
                      className={inputClass}
                    >
                      <option value="">
                        Any time
                      </option>
                      <option value="morning">
                        Morning (06:00–11:59)
                      </option>
                      <option value="afternoon">
                        Afternoon (12:00–17:59)
                      </option>
                      <option value="evening">
                        Evening (18:00–05:59)
                      </option>
                    </select>
                  </div>
                </div>

                <div className="mt-4 flex justify-end gap-2">
                  <button
                    type="button"
                    onClick={clearFilters}
                    className="rounded border border-[#D8CBB8] px-4 py-2 text-sm text-[#51483F] hover:bg-[#EAE4D9]"
                  >
                    Clear all
                  </button>

                  <button
                    type="button"
                    onClick={applyFilters}
                    className="rounded bg-[#51483F] px-4 py-2 text-sm text-white hover:bg-[#39352F]"
                  >
                    Apply filters
                  </button>
                </div>
              </div>
            )}

            {/* Case table */}
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="bg-[#EAE4D9] text-xs text-[#51483F]">
                  <tr>
                    <th className="px-5 py-3 font-medium">
                      Case ID
                    </th>

                    <th className="px-5 py-3 font-medium">
                      Customer
                    </th>

                    <th className="px-5 py-3 font-medium">
                      Status
                    </th>

                    <th className="px-5 py-3 text-right font-medium">
                      Received
                    </th>
                  </tr>
                </thead>

                <tbody>
                  {filteredCases.map((caseItem) => (
                    <tr
                      key={caseItem.id}
                      className="border-t border-[#DDD5C9] even:bg-[#F4F0E9] hover:bg-[#E8DED0]"
                    >
                      <td className="px-5 py-4 font-medium">
                        {caseItem.lockedBy ? (
                          <span
                            className="cursor-not-allowed text-[#756B60]"
                            title={`In use by ${caseItem.lockedBy}`}
                          >
                            {caseItem.id}
                          </span>
                        ) : (
                          <Link
                            href={`/cases/${caseItem.id}`}
                            className="text-[#51483F] underline-offset-4 hover:underline"
                          >
                            {caseItem.id}
                          </Link>
                        )}
                      </td>

                      <td className="px-5 py-4">
                        {caseItem.customer}
                      </td>

                      <td className="px-5 py-4">
                        <div>{caseItem.status}</div>

                        {caseItem.lockedBy && (
                          <div className="mt-1 text-xs font-medium text-[#756B60]">
                            🔒 In use by {caseItem.lockedBy}
                          </div>
                        )}
                      </td>

                      <td className="px-5 py-4 text-right text-[#756B60]">
                        {caseItem.received}
                      </td>
                    </tr>
                  ))}

                  {loading && (
                    <tr>
                      <td colSpan={4} className="px-5 py-10 text-center text-sm text-[#756B60]">
                        Loading cases...
                      </td>
                    </tr>
                  )}

                  {!loading && loadError && (
                    <tr>
                      <td colSpan={4} role="alert" className="px-5 py-10 text-center text-sm text-red-700">
                        Unable to load cases. Please try refreshing the page.
                      </td>
                    </tr>
                  )}

                  {!loading && !loadError && filteredCases.length === 0 && (
                    <tr>
                      <td
                        colSpan={4}
                        className="px-5 py-10 text-center text-sm text-[#756B60]"
                      >
                        No cases match the selected filters.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>

          <p className="mt-4 text-xs text-[#756B60]">
            Cases are retrieved from your organisation&apos;s authenticated workspace.
            Exclusive case access is connected to live records. Additional case actions are under development.
          </p>
        </div>
      </div>
    </main>
  );
}
