import { Component, computed, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { ExamService } from '../../core/services/exam.service';
import { AcademicService } from '../../core/services/academic.service';
import { AuthStore } from '../../core/auth/auth.store';
import { AcademicYearStore } from '../../core/state/academic-year.store';
import { NotificationService } from '../../core/services/notification.service';
import {
  Exam,
  ExamMarksSheetRow,
  ExamSubjectOption,
  ImportPreview,
  Section
} from '../../core/models/api.models';
import { ExamTabsComponent } from './exam-tabs.component';

/** Marks entry (screen 5): Exam -> Class -> Section -> Subject -> roster grid. */
@Component({
  selector: 'app-marks-entry',
  imports: [FormsModule, ExamTabsComponent],
  templateUrl: './marks-entry.component.html',
  styleUrl: './marks-entry.component.scss'
})
export class MarksEntryComponent {
  private readonly api = inject(ExamService);
  private readonly academic = inject(AcademicService);
  private readonly notify = inject(NotificationService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  protected readonly store = inject(AuthStore);
  private readonly yearStore = inject(AcademicYearStore);

  protected readonly exams = signal<Exam[]>([]);
  protected readonly sections = signal<Section[]>([]);
  protected readonly subjects = signal<ExamSubjectOption[]>([]);
  protected readonly rows = signal<ExamMarksSheetRow[]>([]);

  protected examId = 0;
  protected classId = 0;
  protected sectionId = 0;
  protected subjectId = 0;
  protected examSubjectId = 0;
  protected maxMarks = 100;

  protected readonly saving = signal(false);
  protected readonly loadingSheet = signal(false);

  // Import dialog
  protected readonly importOpen = signal(false);
  protected readonly importPreview = signal<ImportPreview | null>(null);
  protected importFile: File | null = null;
  protected importing = signal(false);

  protected readonly canMarks = this.store.hasPermission('exam.marks');

  // Client-side roster search (roll number / admission number / name).
  protected readonly search = signal('');
  protected readonly filteredRows = computed(() => {
    const q = this.search().trim().toLowerCase();
    const rows = this.rows();
    if (!q) return rows;
    return rows.filter((r) =>
      (r.admission_number ?? '').toLowerCase().includes(q) ||
      (r.roll_number ?? '').toLowerCase().includes(q) ||
      `${r.first_name} ${r.last_name}`.toLowerCase().includes(q)
    );
  });

  /** Dropdown label that makes exams across different years distinguishable. */
  protected examLabel(e: Exam): string {
    const year = e.academic_year_name ?? (e.start_date ? new Date(e.start_date).getFullYear().toString() : null);
    return year ? `${e.name} — ${year}` : e.name;
  }

  constructor() {
    this.yearStore.load();
    // Reload the exam dropdown whenever the header year changes (scopes exams by year).
    effect(() => {
      const year = this.yearStore.filterId();
      this.api.list({ academicYearId: year }).subscribe((e) => {
        this.exams.set(e);
        this.restoreFromUrl();
      });
    });
  }

  /**
   * Rebuild the selection (exam -> class -> section -> subject) from the URL query
   * params and load the roster automatically. This means a teacher who saved marks
   * and later returns (or refreshes) lands straight back on the same sheet with
   * their saved marks visible, instead of a blank screen.
   */
  private restoreFromUrl(): void {
    const q = this.route.snapshot.queryParamMap;
    const examId = Number(q.get('exam')) || 0;
    const classId = Number(q.get('class')) || 0;
    const sectionId = Number(q.get('section')) || 0;
    const subjectId = Number(q.get('subject')) || 0;
    if (!examId || !classId) return;
    if (!this.exams().some((e) => e.exam_id === examId)) return;

    this.examId = examId;
    this.classId = classId;
    // Load the dependent dropdowns, then restore section/subject and load the sheet.
    this.academic.listSections(classId).subscribe((s) => {
      this.sections.set(s);
      if (sectionId && s.some((x) => x.section_id === sectionId)) this.sectionId = sectionId;
    });
    this.api.subjectsForClass(examId, classId).subscribe((subs) => {
      this.subjects.set(subs);
      const subj = subs.find((x) => x.subject_id === subjectId) ?? subs[0];
      if (subj) {
        this.subjectId = subj.subject_id;
        this.examSubjectId = subj.exam_subject_id;
        this.maxMarks = subj.max_marks;
        this.loadSheet();
      }
    });
  }

  /** Mirror the current selection into the URL so it survives refresh / navigation. */
  private syncUrl(): void {
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: {
        exam: this.examId || null,
        class: this.classId || null,
        section: this.sectionId || null,
        subject: this.subjectId || null
      },
      queryParamsHandling: 'merge',
      replaceUrl: true
    });
  }

  /** Classes available for the chosen exam. */
  protected classesForExam(): { class_id: number; name: string }[] {
    return this.exams().find((e) => e.exam_id === this.examId)?.classes ?? [];
  }

  protected onExamChange(): void {
    this.classId = 0; this.sectionId = 0; this.subjectId = 0; this.examSubjectId = 0;
    this.sections.set([]); this.subjects.set([]); this.rows.set([]);
  }

  protected onClassChange(): void {
    this.sectionId = 0; this.subjectId = 0; this.examSubjectId = 0;
    this.subjects.set([]); this.rows.set([]);
    this.sections.set([]);
    if (this.classId) {
      this.academic.listSections(this.classId).subscribe((s) => this.sections.set(s));
      this.api.subjectsForClass(this.examId, this.classId).subscribe((s) => this.subjects.set(s));
    }
  }

  protected onSubjectChange(): void {
    this.rows.set([]);
    const subj = this.subjects().find((s) => s.subject_id === this.subjectId);
    this.examSubjectId = subj?.exam_subject_id ?? 0;
    this.maxMarks = subj?.max_marks ?? 100;
    // Auto-load the roster (with any saved marks) as soon as a subject is chosen.
    if (this.canLoad()) this.loadSheet();
  }

  protected onSectionChange(): void {
    // Reload the roster for the newly chosen section if a subject is already picked.
    if (this.canLoad()) this.loadSheet();
  }

  protected canLoad(): boolean {
    return !!(this.examId && this.classId && this.examSubjectId);
  }

  protected loadSheet(): void {
    if (!this.canLoad()) { this.notify.info('Select exam, class and subject.'); return; }
    this.syncUrl();
    this.loadingSheet.set(true);
    this.api.marksSheet(this.examSubjectId, this.sectionId || undefined).subscribe({
      next: (s) => {
        this.loadingSheet.set(false);
        // Keep marks as numbers so the number inputs show the saved values.
        this.rows.set(s?.items ? s.items.map((r) => ({
          ...r,
          marks: r.marks === null || r.marks === undefined ? null : Number(r.marks)
        })) : []);
        if (s) this.maxMarks = s.max_marks;
      },
      error: () => { this.loadingSheet.set(false); this.notify.error('Could not load the sheet.'); }
    });
  }

  private save(draft: boolean): void {
    if (!this.rows().length || this.saving()) return;
    this.saving.set(true);
    this.api.saveMarks({
      ExamSubjectId: this.examSubjectId,
      Entries: this.rows().map((r) => ({
        StudentId: r.student_id,
        Marks: r.is_absent ? null : (r.marks ?? null),
        IsAbsent: r.is_absent
      }))
    }).subscribe({
      next: (res) => {
        this.saving.set(false);
        if (res.isSuccess) {
          this.notify.success(draft ? 'Draft saved.' : 'Marks saved.');
          this.loadSheet();
        } else {
          this.notify.error(res.resultCodeDescription ?? 'Save failed.');
        }
      },
      error: () => this.saving.set(false)
    });
  }

  protected saveMarks(): void { this.save(false); }
  protected saveDraft(): void { this.save(true); }

  protected statusOf(r: ExamMarksSheetRow): string {
    if (r.is_absent) return 'Absent';
    if (r.marks !== null && r.marks !== undefined) return 'Entered';
    return 'Pending';
  }

  // ---- Excel ----
  protected exportTemplate(): void {
    if (!this.examSubjectId) { this.notify.info('Select a subject first.'); return; }
    window.open(this.api.templateUrl(this.examSubjectId, this.sectionId || undefined), '_blank');
  }

  protected openImport(): void {
    if (!this.examSubjectId) { this.notify.info('Select a subject first.'); return; }
    this.importFile = null;
    this.importPreview.set(null);
    this.importOpen.set(true);
  }

  protected closeImport(): void {
    this.importOpen.set(false);
  }

  protected onFile(ev: Event): void {
    const input = ev.target as HTMLInputElement;
    this.importFile = input.files?.[0] ?? null;
  }

  protected runImport(): void {
    if (!this.importFile) { this.notify.info('Choose an .xlsx file.'); return; }
    this.importing.set(true);
    this.api.importMarks(this.examSubjectId, this.importFile, this.sectionId || undefined).subscribe({
      next: (p) => {
        this.importing.set(false);
        this.importPreview.set(p);
        if (!p) this.notify.error('Could not read the file.');
      },
      error: () => { this.importing.set(false); this.notify.error('Import failed. Check the file format.'); }
    });
  }

  /** Apply valid preview rows onto the grid (does not save until the user clicks Save). */
  protected applyImport(): void {
    const p = this.importPreview();
    if (!p) return;
    const byId = new Map(p.rows.filter((r) => r.status === 'Valid').map((r) => [r.student_id, r]));
    this.rows.update((rows) => rows.map((r) => {
      const m = byId.get(r.student_id);
      return m ? { ...r, marks: m.marks, is_absent: m.is_absent } : r;
    }));
    this.closeImport();
    this.notify.success(`Applied ${byId.size} imported row(s). Review and Save.`);
  }
}
