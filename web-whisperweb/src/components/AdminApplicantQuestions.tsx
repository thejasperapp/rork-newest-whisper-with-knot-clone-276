import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Plus,
  Trash2,
  GripVertical,
  Eye,
  EyeOff,
  Loader2,
  Save,
  X,
  Type,
  AlignLeft,
  List,
  Hash,
  Star,
} from "lucide-react";
import { toast } from "sonner";

import {
  fetchAllQuestions,
  createQuestion,
  updateQuestion,
  deleteQuestion,
  type ApplicantQuestion,
} from "@/lib/applicantQuestionnaire";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";

const TYPE_META: Record<string, { label: string; icon: typeof Type }> = {
  text: { label: "Short text", icon: Type },
  textarea: { label: "Long text", icon: AlignLeft },
  select: { label: "Multiple choice", icon: List },
  number: { label: "Number", icon: Hash },
  rating: { label: "Rating (1-5)", icon: Star },
};

export function AdminApplicantQuestions() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);

  const questionsQuery = useQuery({
    queryKey: ["admin-applicant-questions", user?.id],
    queryFn: fetchAllQuestions,
    enabled: !!user,
  });

  const questions = questionsQuery.data ?? [];

  const deleteMutation = useMutation({
    mutationFn: deleteQuestion,
    onSuccess: () => {
      toast.success("Question deleted");
      queryClient.invalidateQueries({ queryKey: ["admin-applicant-questions"] });
    },
    onError: () => toast.error("Could not delete question"),
  });

  const toggleActiveMutation = useMutation({
    mutationFn: ({ id, isActive }: { id: string; isActive: boolean }) =>
      updateQuestion(id, { is_active: isActive }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["admin-applicant-questions"] });
    },
    onError: () => toast.error("Could not update question"),
  });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold">Applicant Questions</h2>
          <p className="text-sm text-muted-foreground">
            Edit the questionnaire that leads see when they scan a recruiter's QR code.
          </p>
        </div>
        <button
          onClick={() => setShowNew(true)}
          className="flex items-center gap-1.5 rounded-full bg-foreground px-4 py-2 text-sm font-bold text-background transition-transform active:scale-95"
        >
          <Plus className="h-4 w-4" />
          Add question
        </button>
      </div>

      {questionsQuery.isLoading ? (
        <div className="flex justify-center py-10">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      ) : questions.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-border bg-card p-8 text-center">
          <p className="text-sm font-bold">No questions yet</p>
          <p className="mt-1 text-xs text-muted-foreground">Add your first question to build the questionnaire.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {questions.map((q, idx) => (
            <div
              key={q.id}
              className={cn(
                "flex items-start gap-3 rounded-2xl border border-border bg-card p-4",
                !q.is_active && "opacity-50"
              )}
            >
              <div className="flex flex-col items-center gap-1 pt-1">
                <GripVertical className="h-4 w-4 text-muted-foreground/50" />
                <span className="text-[10px] font-bold text-muted-foreground">{idx + 1}</span>
              </div>

              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <p className="truncate text-sm font-bold">{q.question}</p>
                  {q.required && (
                    <span className="rounded-full bg-foreground px-1.5 py-0.5 text-[9px] font-bold uppercase text-background">
                      Required
                    </span>
                  )}
                </div>
                <div className="mt-1 flex items-center gap-2 text-xs text-muted-foreground">
                  {(() => {
                    const meta = TYPE_META[q.question_type];
                    const Icon = meta?.icon ?? Type;
                    return (
                      <>
                        <Icon className="h-3 w-3" />
                        {meta?.label ?? q.question_type}
                      </>
                    );
                  })()}
                  {q.options && q.options.length > 0 && (
                    <span>· {q.options.length} options</span>
                  )}
                </div>
              </div>

              <div className="flex items-center gap-1">
                <button
                  onClick={() => toggleActiveMutation.mutate({ id: q.id, isActive: !q.is_active })}
                  className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary transition-colors hover:bg-secondary/80"
                  title={q.is_active ? "Hide" : "Show"}
                >
                  {q.is_active ? <Eye className="h-4 w-4" /> : <EyeOff className="h-4 w-4" />}
                </button>
                <button
                  onClick={() => setEditingId(q.id)}
                  className="rounded-full bg-secondary px-3 py-1.5 text-xs font-bold transition-colors hover:bg-secondary/80"
                >
                  Edit
                </button>
                <button
                  onClick={() => {
                    if (confirm("Delete this question?")) deleteMutation.mutate(q.id);
                  }}
                  className="flex h-8 w-8 items-center justify-center rounded-full bg-red-500/10 text-red-500 transition-colors hover:bg-red-500/20"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {showNew && (
        <QuestionEditor
          onClose={() => setShowNew(false)}
          onSaved={() => {
            setShowNew(false);
            queryClient.invalidateQueries({ queryKey: ["admin-applicant-questions"] });
          }}
        />
      )}

      {editingId && (
        <QuestionEditor
          question={questions.find((q) => q.id === editingId)}
          onClose={() => setEditingId(null)}
          onSaved={() => {
            setEditingId(null);
            queryClient.invalidateQueries({ queryKey: ["admin-applicant-questions"] });
          }}
        />
      )}
    </div>
  );
}

function QuestionEditor({
  question,
  onClose,
  onSaved,
}: {
  question?: ApplicantQuestion;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [text, setText] = useState(question?.question ?? "");
  const [type, setType] = useState<string>(question?.question_type ?? "text");
  const [required, setRequired] = useState(question?.required ?? true);
  const [options, setOptions] = useState((question?.options ?? []).join("\n"));
  const [busy, setBusy] = useState(false);

  const showOptions = type === "select";

  const save = async () => {
    if (!text.trim()) {
      toast.error("Question text is required");
      return;
    }
    setBusy(true);
    try {
      const optionsArray = showOptions
        ? options.split("\n").map((o) => o.trim()).filter(Boolean)
        : null;

      if (question) {
        await updateQuestion(question.id, {
          question: text.trim(),
          question_type: type as ApplicantQuestion["question_type"],
          required,
          options: optionsArray,
        });
        toast.success("Question updated");
      } else {
        await createQuestion({
          question: text.trim(),
          question_type: type as ApplicantQuestion["question_type"],
          required,
          options: optionsArray,
        });
        toast.success("Question added");
      }
      onSaved();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Could not save question");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm" onClick={onClose}>
      <div
        className="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-t-3xl border border-border bg-background p-5"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-bold">{question ? "Edit question" : "New question"}</h2>
          <button onClick={onClose} className="rounded-full bg-secondary p-2">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="space-y-4">
          {/* Question text */}
          <div>
            <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">Question</label>
            <textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder="e.g. What is your preferred sport?"
              rows={2}
              className="w-full resize-none rounded-2xl border border-border bg-card px-4 py-3 text-[15px] outline-none focus:border-foreground/40"
            />
          </div>

          {/* Type selector */}
          <div>
            <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">Answer type</label>
            <div className="grid grid-cols-3 gap-2">
              {Object.entries(TYPE_META).map(([key, meta]) => {
                const Icon = meta.icon;
                return (
                  <button
                    key={key}
                    onClick={() => setType(key)}
                    className={cn(
                      "flex flex-col items-center gap-1 rounded-xl border py-3 text-xs font-semibold transition-all",
                      type === key
                        ? "border-foreground bg-foreground text-background"
                        : "border-border bg-card text-foreground"
                    )}
                  >
                    <Icon className="h-4 w-4" />
                    {meta.label}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Options (for select) */}
          {showOptions && (
            <div>
              <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">
                Options (one per line)
              </label>
              <textarea
                value={options}
                onChange={(e) => setOptions(e.target.value)}
                placeholder={"Option 1\nOption 2\nOption 3"}
                rows={5}
                className="w-full resize-none rounded-2xl border border-border bg-card px-4 py-3 text-[15px] outline-none focus:border-foreground/40"
              />
            </div>
          )}

          {/* Required toggle */}
          <label className="flex cursor-pointer items-center gap-3 rounded-2xl border border-border bg-card p-4">
            <input
              type="checkbox"
              checked={required}
              onChange={(e) => setRequired(e.target.checked)}
              className="h-5 w-5 rounded accent-foreground"
            />
            <div>
              <p className="text-sm font-bold">Required</p>
              <p className="text-xs text-muted-foreground">Applicants must answer this to submit.</p>
            </div>
          </label>

          {/* Save */}
          <button
            onClick={save}
            disabled={busy}
            className="flex w-full items-center justify-center gap-2 rounded-2xl bg-foreground py-3.5 text-sm font-bold text-background transition-transform active:scale-[0.98] disabled:opacity-50"
          >
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
            {question ? "Save changes" : "Add question"}
          </button>
        </div>
      </div>
    </div>
  );
}
