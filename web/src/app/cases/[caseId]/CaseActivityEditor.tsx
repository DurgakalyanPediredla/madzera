"use client";

import { useRef, useState } from "react";

type CaseActivityEditorProps = {
  onSave: (comment: string) => Promise<void>;
};

export default function CaseActivityEditor({
  onSave,
}: CaseActivityEditorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [comment, setComment] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const savingRef = useRef(false);

  function closeEditor() {
    if (savingRef.current) return;
    setIsOpen(false);
    setComment("");
    setError(null);
  }

  async function saveActivity() {
    if (savingRef.current) return;

    const body = comment.trim();

    if (!body || body.length > 10000) {
      setError("Enter a work update between 1 and 10,000 characters.");
      return;
    }

    savingRef.current = true;
    setSaving(true);
    setError(null);

    try {
      await onSave(body);
      setComment("");
      setIsOpen(false);
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Unable to save this activity. Please try again."
      );
    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  }

  return (
    <div className="contents">
      {!isOpen ? (
        <button
          type="button"
          onClick={() => setIsOpen(true)}
          className="w-fit justify-self-end rounded-md bg-[#51483F] px-4 py-2 text-sm font-medium text-white hover:bg-[#39352F]"
        >
          + Add Activity
        </button>
      ) : (
        <div className="col-span-full w-full rounded-lg border border-[#D8CBB8] bg-white p-6">
          <label
            htmlFor="activity-comment"
            className="block text-sm font-semibold text-[#39352F]"
          >
            Work update / Handover comment
          </label>

          <textarea
            id="activity-comment"
            value={comment}
            onChange={(event) => setComment(event.target.value)}
            disabled={saving}
            maxLength={10000}
            rows={6}
            placeholder="Describe the work completed, information reviewed, or instructions for the next employee..."
            className="mt-3 w-full rounded-md border border-[#C9BBA7] p-4 text-sm leading-6 text-[#39352F] outline-none focus:border-[#51483F] disabled:opacity-60"
          />

          <p className="mt-3 text-xs text-[#756B60]">
            Internal employee comments are saved to the case activity record.
            Supporting attachments are not yet available.
          </p>

          {error && (
            <p role="alert" className="mt-4 text-sm text-red-700">
              {error}
            </p>
          )}

          <div className="mt-5 flex justify-end gap-3">
            <button
              type="button"
              onClick={closeEditor}
              disabled={saving}
              className="rounded-md border border-[#C9BBA7] px-4 py-2 text-sm text-[#39352F] hover:bg-[#F4F0E9] disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={() => void saveActivity()}
              disabled={saving || !comment.trim()}
              className="rounded-md bg-[#51483F] px-4 py-2 text-sm font-medium text-white hover:bg-[#39352F] disabled:opacity-50"
            >
              {saving ? "Saving..." : "Save Activity"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
