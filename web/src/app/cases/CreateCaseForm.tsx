"use client";

import { useEffect, useState, type FormEvent } from "react";
import { supabase } from "@/lib/supabase";

type Customer = {
  id: string;
  name: string;
};

type Team = {
  id: string;
  name: string;
};

type CaseOrigin = "customer" | "internal";
type Priority = "low" | "medium" | "high" | "critical";

type Props = {
  onCreated: (caseId: string, origin: CaseOrigin) => void;
  onCancel: () => void;
};

export default function CreateCaseForm({
  onCreated,
  onCancel,
}: Props) {
  const [origin, setOrigin] = useState<CaseOrigin>("customer");
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [teams, setTeams] = useState<Team[]>([]);
  const [customerId, setCustomerId] = useState("");
  const [teamId, setTeamId] = useState("");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [priority, setPriority] = useState<Priority>("medium");
  const [loadingOptions, setLoadingOptions] = useState(true);
  const [saving, setSaving] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    async function loadOptions() {
      const [customerResult, teamResult] = await Promise.all([
        supabase.from("customers").select("id, name").order("name"),
        supabase.from("teams").select("id, name").order("name"),
      ]);

      if (!active) return;

      if (customerResult.error || teamResult.error) {
        setError("Unable to load customers or teams.");
      } else {
        setCustomers(customerResult.data ?? []);
        setTeams(teamResult.data ?? []);
      }

      setLoadingOptions(false);
    }

    void loadOptions();

    return () => {
      active = false;
    };
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (saving || loadingOptions) return;

    setError(null);

    if (!title.trim()) {
      setError("Case title is required.");
      return;
    }

    if (origin === "customer" && !customerId) {
      setError("Select a customer for a customer enquiry.");
      return;
    }

    if (!teamId) {
      setError("Select the team responsible for this case.");
      return;
    }

    if (!reviewing) {
      setReviewing(true);
      return;
    }

    setSaving(true);

    try {
      const { data, error: createError } = await supabase.rpc(
        "create_employee_case",
        {
          p_title: title.trim(),
          p_description: description.trim() || null,
          p_priority: priority,
          p_customer_id: origin === "customer" ? customerId : null,
          p_assigned_team_id: teamId,
        }
      );

      if (createError) throw createError;
      if (typeof data !== "string") {
        throw new Error("Case creation did not return a case ID.");
      }

      onCreated(data, origin);
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : "Unable to create case."
      );
    } finally {
      setSaving(false);
    }
  }

  const selectedCustomer = customers.find(
    (customer) => customer.id === customerId
  );
  const selectedTeam = teams.find((team) => team.id === teamId);

  if (reviewing) {
    return (
      <form
        onSubmit={(event) => void handleSubmit(event)}
        className="space-y-4 rounded-lg border border-[#D8CBB8] bg-white p-5"
      >
        <h2 className="text-lg font-semibold">Review Case Details</h2>
        <p className="text-sm text-[#756B60]">
          Check the details before creating this case. No case has been
          created yet.
        </p>

        <dl className="grid gap-4 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-[#756B60]">Case type</dt>
            <dd className="font-medium">
              {origin === "customer" ? "Customer enquiry" : "Internal case"}
            </dd>
          </div>

          {origin === "customer" && (
            <div>
              <dt className="text-[#756B60]">Customer</dt>
              <dd className="font-medium">
                {selectedCustomer?.name ?? "Unknown customer"}
              </dd>
            </div>
          )}

          <div>
            <dt className="text-[#756B60]">Priority</dt>
            <dd className="font-medium capitalize">{priority}</dd>
          </div>

          <div>
            <dt className="text-[#756B60]">Assigned team</dt>
            <dd className="font-medium">
              {selectedTeam?.name ?? "Unknown team"}
            </dd>
          </div>

          <div className="sm:col-span-2">
            <dt className="text-[#756B60]">Case title</dt>
            <dd className="font-medium break-words">{title.trim()}</dd>
          </div>

          <div className="sm:col-span-2">
            <dt className="text-[#756B60]">Description</dt>
            <dd className="whitespace-pre-wrap break-words">
              {description.trim() || "No description provided"}
            </dd>
          </div>
        </dl>

        {error && (
          <p role="alert" className="text-sm text-red-700">
            {error}
          </p>
        )}

        <div className="flex justify-end gap-3">
          <button
            type="button"
            onClick={() => {
              setReviewing(false);
              setError(null);
            }}
            disabled={saving}
            className="rounded border border-[#D8CBB8] px-4 py-2 text-sm disabled:opacity-50"
          >
            Back to Edit
          </button>

          <button
            type="submit"
            disabled={saving}
            className="rounded bg-[#51483F] px-5 py-2 text-sm font-medium text-white disabled:opacity-50"
          >
            {saving ? "Creating..." : "Confirm & Create Case"}
          </button>
        </div>
      </form>
    );
  }

  return (
    <form
      onSubmit={(event) => void handleSubmit(event)}
      className="space-y-4 rounded-lg border border-[#D8CBB8] bg-white p-5"
    >
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">Create New Case</h2>
        <button
          type="button"
          onClick={onCancel}
          disabled={saving}
          className="text-sm underline disabled:opacity-50"
        >
          Cancel
        </button>
      </div>

      <div>
        <label htmlFor="create-origin" className="mb-1 block text-sm">
          Case type
        </label>
        <select
          id="create-origin"
          value={origin}
          onChange={(event) => {
            setOrigin(event.target.value as CaseOrigin);
            setError(null);
          }}
          disabled={saving}
          className="w-full rounded border p-2 text-sm"
        >
          <option value="customer">Customer enquiry</option>
          <option value="internal">Internal case</option>
        </select>
      </div>

      {origin === "customer" && (
        <div>
          <label htmlFor="create-customer" className="mb-1 block text-sm">
            Customer
          </label>
          <select
            id="create-customer"
            value={customerId}
            onChange={(event) => setCustomerId(event.target.value)}
            disabled={saving || loadingOptions}
            required
            className="w-full rounded border p-2 text-sm"
          >
            <option value="">Select customer</option>
            {customers.map((customer) => (
              <option key={customer.id} value={customer.id}>
                {customer.name}
              </option>
            ))}
          </select>
        </div>
      )}

      <div>
        <label htmlFor="create-title" className="mb-1 block text-sm">
          Case title
        </label>
        <input
          id="create-title"
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          maxLength={255}
          required
          disabled={saving}
          className="w-full rounded border p-2 text-sm"
        />
      </div>

      <div>
        <label htmlFor="create-description" className="mb-1 block text-sm">
          Description
        </label>
        <textarea
          id="create-description"
          value={description}
          onChange={(event) => setDescription(event.target.value)}
          rows={4}
          disabled={saving}
          className="w-full rounded border p-2 text-sm"
        />
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor="create-priority" className="mb-1 block text-sm">
            Priority
          </label>
          <select
            id="create-priority"
            value={priority}
            onChange={(event) =>
              setPriority(event.target.value as Priority)
            }
            disabled={saving}
            className="w-full rounded border p-2 text-sm"
          >
            <option value="low">Low</option>
            <option value="medium">Medium</option>
            <option value="high">High</option>
            <option value="critical">Critical</option>
          </select>
        </div>

        <div>
          <label htmlFor="create-team" className="mb-1 block text-sm">
            Assign to team
          </label>
          <select
            id="create-team"
            value={teamId}
            onChange={(event) => setTeamId(event.target.value)}
            disabled={saving || loadingOptions}
            required
            className="w-full rounded border p-2 text-sm"
          >
            <option value="">Select team</option>
            {teams.map((team) => (
              <option key={team.id} value={team.id}>
                {team.name}
              </option>
            ))}
          </select>
        </div>
      </div>

      <p className="text-xs text-[#756B60]">
        Supporting documents will be available after secure
        evidence uploads are implemented.
      </p>

      {error && (
        <p role="alert" className="text-sm text-red-700">
          {error}
        </p>
      )}

      <div className="flex justify-end">
        <button
          type="submit"
          disabled={saving || loadingOptions || Boolean(error && loadingOptions)}
          className="rounded bg-[#51483F] px-5 py-2 text-sm font-medium text-white disabled:opacity-50"
        >
          {saving ? "Creating..." : "Review Case"}
        </button>
      </div>
    </form>
  );
}
