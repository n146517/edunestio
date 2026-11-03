import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe } from '@angular/common';
import { AssignmentService } from '../../core/services/assignment.service';
import { TimetableService } from '../../core/services/timetable.service';
import { AcademicService } from '../../core/services/academic.service';
import { AuthStore } from '../../core/auth/auth.store';
import { NotificationService } from '../../core/services/notification.service';
import {
  Assignment, AssignmentSubmission, SchoolClass, Section, Subject, Teacher
} from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

/** Staff: create/list assignments, review and grade submissions. */
@Component({
  selector: 'app-assignments',
  imports: [FormsModule, DatePipe],
  templateUrl: './assignments.component.html',
  styleUrl: './assignments.component.scss'
})
export class AssignmentsComponent {
  private readonly api = inject(AssignmentService);
  private readonly tt = inject(TimetableService);
  private readonly academic = inject(AcademicService);
  private readonly notify = inject(NotificationService);
  protected readonly store = inject(AuthStore);

  protected readonly state = signal<LoadState>('loading');
  protected readonly items = signal<Assignment[]>([]);
  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly sections = signal<Section[]>([]);
  protected readonly subjects = signal<Subject[]>([]);
  protected readonly teachers = signal<Teacher[]>([]);

  protected filterClassId = 0;

  protected readonly canManage = this.store.hasPermission('assignment.manage');

  // Create/edit dialog.
  protected readonly editorOpen = signal(false);
  protected editId: number | null = null;
  protected fClassId = 0;
  protected fSectionId = 0;
  protected fSubjectId = 0;
  protected fTeacherId = 0;
  protected fTitle = '';
  protected fDesc = '';
  protected fDue = '';
  protected fMax: number | null = null;
  protected readonly editSections = signal<Section[]>([]);
  protected readonly busy = signal(false);

  // Submissions dialog.
  protected readonly subsOpen = signal(false);
  protected readonly subsFor = signal<Assignment | null>(null);
  protected readonly subs = signal<AssignmentSubmission[]>([]);
  protected readonly subsLoading = signal(false);

  constructor() {
    this.academic.listClasses().subscribe((c) => this.classes.set(c));
    this.academic.listSubjects().subscribe((s) => this.subjects.set(s.filter((x) => x.is_active)));
    if (this.canManage) this.tt.teachers().subscribe((t) => this.teachers.set(t));
    this.load();
  }

  protected load(): void {
    this.state.set('loading');
    this.api.list({ classId: this.filterClassId || undefined }).subscribe({
      next: (a) => { this.items.set(a); this.state.set('success'); },
      error: () => this.state.set('error')
    });
  }

  // ---- Create / edit ----
  protected openCreate(): void {
    this.editId = null;
    this.fClassId = 0; this.fSectionId = 0; this.fSubjectId = 0; this.fTeacherId = 0;
    this.fTitle = ''; this.fDesc = ''; this.fDue = ''; this.fMax = null;
    this.editSections.set([]);
    this.editorOpen.set(true);
  }

  protected openEdit(a: Assignment): void {
    this.editId = a.assignment_id;
    this.fClassId = a.class_id; this.fSectionId = a.section_id ?? 0;
    this.fSubjectId = a.subject_id ?? 0; this.fTeacherId = a.teacher_id ?? 0;
    this.fTitle = a.title; this.fDesc = a.description ?? '';
    this.fDue = a.due_date ? a.due_date.substring(0, 10) : '';
    this.fMax = a.max_marks;
    this.editSections.set([]);
    if (a.class_id) this.academic.listSections(a.class_id).subscribe((s) => this.editSections.set(s));
    this.editorOpen.set(true);
  }

  protected onEditClassChange(): void {
    this.fSectionId = 0;
    this.editSections.set([]);
    if (this.fClassId) this.academic.listSections(this.fClassId).subscribe((s) => this.editSections.set(s));
  }

  protected closeEditor(): void { this.editorOpen.set(false); }

  protected saveAssignment(): void {
    if (!this.fClassId) { this.notify.info('Choose a class.'); return; }
    if (!this.fTitle.trim()) { this.notify.info('Enter a title.'); return; }
    if (this.busy()) return;
    this.busy.set(true);
    this.api.save({
      AssignmentId: this.editId,
      ClassId: this.fClassId,
      SectionId: this.fSectionId || null,
      SubjectId: this.fSubjectId || null,
      TeacherId: this.fTeacherId || null,
      Title: this.fTitle.trim(),
      Description: this.fDesc || null,
      DueDate: this.fDue || null,
      MaxMarks: this.fMax
    }).subscribe({
      next: (res) => {
        this.busy.set(false);
        if (res.isSuccess) { this.notify.success('Assignment saved.'); this.closeEditor(); this.load(); }
        else this.notify.error(res.resultCodeDescription ?? 'Could not save.');
      },
      error: () => this.busy.set(false)
    });
  }

  protected deleteAssignment(a: Assignment): void {
    if (!confirm(`Delete "${a.title}"? This removes its submissions too.`)) return;
    this.api.delete(a.assignment_id).subscribe({
      next: (res) => {
        if (res.isSuccess) { this.notify.success('Deleted.'); this.load(); }
        else this.notify.error(res.resultCodeDescription ?? 'Could not delete.');
      }
    });
  }

  // ---- Submissions / grading ----
  protected openSubmissions(a: Assignment): void {
    this.subsFor.set(a);
    this.subs.set([]);
    this.subsOpen.set(true);
    this.subsLoading.set(true);
    this.api.submissions(a.assignment_id).subscribe({
      next: (s) => { this.subs.set(s); this.subsLoading.set(false); },
      error: () => this.subsLoading.set(false)
    });
  }

  protected closeSubs(): void { this.subsOpen.set(false); }

  protected grade(row: AssignmentSubmission): void {
    if (!row.submission_id) { this.notify.info('This student has not submitted yet.'); return; }
    const marksStr = prompt(`Marks for ${row.first_name} ${row.last_name}` +
      (this.subsFor()?.max_marks ? ` (out of ${this.subsFor()!.max_marks})` : '') + ':', row.marks?.toString() ?? '');
    if (marksStr === null) return;
    const marks = marksStr.trim() === '' ? null : Number(marksStr);
    if (marks !== null && isNaN(marks)) { this.notify.error('Marks must be a number.'); return; }
    const feedback = prompt('Feedback (optional):', row.feedback ?? '');
    this.api.grade(row.submission_id, marks, feedback).subscribe({
      next: (res) => {
        if (res.isSuccess) {
          this.notify.success('Graded.');
          const a = this.subsFor();
          if (a) this.openSubmissionsRefresh(a.assignment_id);
        } else this.notify.error(res.resultCodeDescription ?? 'Could not grade.');
      }
    });
  }

  private openSubmissionsRefresh(assignmentId: number): void {
    this.api.submissions(assignmentId).subscribe((s) => this.subs.set(s));
  }

  protected submittedCount(): number {
    return this.subs().filter((s) => s.status).length;
  }
}
