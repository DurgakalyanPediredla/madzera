
"use client";

import { useRef, useState } from "react";

export default function CaseActivityEditor() {
  const [isOpen, setIsOpen] = useState(false);
  const [comment, setComment] = useState("");
  const [attachments, setAttachments] = useState<File[]>([]);

  const fileInputRef = useRef<HTMLInputElement>(null);

  function closeEditor() {
    setIsOpen(false);
    setComment("");
    setAttachments([]);

    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  }

  function addAttachments(files: FileList | null) {
    if (!files) return;

    setAttachments((previous) => [
      ...previous,
      ...Array.from(files),
    ]);

    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  }

  function removeAttachment(index: number) {
    setAttachments((previous) =>
      previous.filter((_, fileIndex) => fileIndex !== index)
    );
  }

  return (
    <div className="contents">
      {/* Show Add Activity only when editor is closed */}
      {!isOpen && (
        <button
          type="button"
          onClick={() => setIsOpen(true)}
          aria-expanded={false}
          className="w-fit justify-self-end rounded-md bg-[#51483F] px-4 py-2 text-sm font-medium text-white hover:bg-[#39352F]"
        >
          + Add Activity
        </button>
      )}

      {isOpen && (
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
            rows={6}
            placeholder="Describe the work completed, information reviewed, or instructions for the next employee..."
            className="mt-3 w-full rounded-md border border-[#C9BBA7] p-4 text-sm leading-6 text-[#39352F] outline-none focus:border-[#51483F]"
          />

          {/* Supporting attachments */}
          <div className="mt-6 border-t border-[#EAE4D9] pt-5">
            <label
              htmlFor="activity-attachments"
              className="block text-sm font-semibold text-[#39352F]"
            >
              Supporting attachments
            </label>

            <p className="mt-1 text-xs text-[#756B60]">
              Select multiple documents to include with this
              case activity.
            </p>

            <input
              ref={fileInputRef}
              id="activity-attachments"
              type="file"
              multiple
              onChange={(event) =>
                addAttachments(event.target.files)
              }
              className="mt-3 block w-full text-sm text-[#51483F] file:mr-4 file:rounded-md file:border file:border-[#C9BBA7] file:bg-[#F4F0E9] file:px-4 file:py-2 file:text-sm file:font-medium file:text-[#39352F] hover:file:bg-[#EAE4D9]"
            />

            {attachments.length > 0 && (
              <div className="mt-4 space-y-2">
                <p className="text-xs font-medium text-[#756B60]">
                  Selected files ({attachments.length})
                </p>

                {attachments.map((file, index) => (
                  <div
                    key={`${file.name}-${index}`}
                    className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-[#EAE4D9] bg-[#FAF9F6] px-4 py-3"
                  >
                    <div className="min-w-0">
                      <p className="break-all text-sm font-medium text-[#39352F]">
                        {file.name}
                      </p>

                      <p className="mt-1 text-xs text-[#756B60]">
                        {(file.size / 1024).toFixed(1)} KB
                      </p>
                    </div>

                    {/* Remove individual attachment */}
                    <button
                      type="button"
                      onClick={() => removeAttachment(index)}
                      className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-lg text-[#756B60] hover:bg-[#EAE4D9] hover:text-[#39352F]"
                      aria-label={`Remove ${file.name}`}
                      title={`Remove ${file.name}`}
                    >
                      ×
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <p className="mt-5 text-xs text-[#756B60]">
            The comment and supporting documents will be
            recorded together under the employee who saves
            the activity.
          </p>

          <div className="mt-5 flex justify-end gap-3">
            <button
              type="button"
              onClick={closeEditor}
              className="rounded-md border border-[#C9BBA7] px-4 py-2 text-sm text-[#39352F] hover:bg-[#F4F0E9]"
            >
              Cancel
            </button>

            <button
              type="button"
              disabled
              title="Database saving will be enabled after authentication and activity storage are connected"
              className="cursor-not-allowed rounded-md bg-[#51483F] px-4 py-2 text-sm font-medium text-white opacity-50"
            >
              Save Activity
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
