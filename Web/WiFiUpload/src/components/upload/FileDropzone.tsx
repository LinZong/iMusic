import { useState } from "react";
import type { Strings } from "../../i18n";

/** File-selection presentation, independent of validation and queue ownership. */
interface FileDropzoneProps {
  /** Localized picker and drag-and-drop labels. */
  strings: Strings;
  /** Whether file input and drag-and-drop are unavailable. */
  disabled: boolean;
  /** Lowercase native extensions used to build the file picker's accept hint. */
  extensions: readonly string[];
  /** Supplies selected browser files to the queue's validation command. */
  onFiles: (files: File[]) => void;
}

/** Owns transient drag feedback and resets the picker so the same file can be selected again. */
export function FileDropzone({
  strings,
  disabled,
  extensions,
  onFiles,
}: FileDropzoneProps) {
  /** Visual drag feedback belonging only to this input component. */
  const [dragging, setDragging] = useState(false);
  return (
    <label
      className={`dropzone ${dragging && !disabled ? "dragging" : ""} ${disabled ? "disabled" : ""}`}
      onDragOver={(event) => {
        event.preventDefault();
        if (!disabled) setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={(event) => {
        event.preventDefault();
        setDragging(false);
        if (!disabled) onFiles(Array.from(event.dataTransfer.files));
      }}
    >
      <span className="upload-symbol" aria-hidden="true">
        ↑
      </span>
      <strong>{strings.choose}</strong>
      <span>{strings.drop}</span>
      <input
        type="file"
        multiple
        accept={extensions.map((extension) => `.${extension}`).join(",")}
        disabled={disabled}
        aria-label={strings.choose}
        onChange={(event) => {
          onFiles(Array.from(event.target.files ?? []));
          event.target.value = "";
        }}
      />
    </label>
  );
}
