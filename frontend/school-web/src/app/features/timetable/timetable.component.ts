import { Component, computed, inject, signal } from '@angular/core';
import { NgTemplateOutlet } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpErrorResponse } from '@angular/common/http';
import { TimetableService } from '../../core/services/timetable.service';
import { AcademicService } from '../../core/services/academic.service';
import { AuthStore } from '../../core/auth/auth.store';
import {
  PeriodKind, PeriodScheduleItem, SchoolClass, Section, Subject, Teacher, TeacherSchedule, TimetableSlot
} from '../../core/models/api.models';

/** A result popup (success / error / info) shown after add, update, clear or a clash. */
interface ResultDialog {
  kind: 'success' | 'error' | 'info';
  title: string;
  message: string;
  lines: string[];
}

/** Editable row of the period-structure editor. */
interface ScheduleRow { kind: PeriodKind; label: string; start_time: string; end_time: string; }

const DEFAULT_PERIODS = 8;

/** Weekly timetable builder: per-class period structure, subject + teacher per slot, teacher clash check. */
@Component({
  selector: 'app-timetable',
  imports: [FormsModule, NgTemplateOutlet],
  templateUrl: './timetable.component.html',
  styleUrl: './timetable.component.scss'
})
export class TimetableComponent {
  private readonly api = inject(TimetableService);
  private readonly academic = inject(AcademicService);
  protected readonly store = inject(AuthStore);

  protected readonly classes = signal<SchoolClass[]>([]);
  protected readonly sections = signal<Section[]>([]);
  protected readonly subjects = signal<Subject[]>([]);
  protected readonly teachers = signal<Teacher[]>([]);
  protected readonly slots = signal<TimetableSlot[]>([]);
  protected readonly schedule = signal<PeriodScheduleItem[]>([]);
  protected readonly loading = signal(false);

  protected classId = 0;
  protected sectionId = 0;

  protected readonly canManage = this.store.hasPermission('timetable.manage');

  /** 'class' = build a class timetable; 'teacher' = see where a teacher teaches. */
  protected readonly tab = signal<'class' | 'teacher'>('class');

  protected readonly days = [
    { n: 1, label: 'Monday' }, { n: 2, label: 'Tuesday' }, { n: 3, label: 'Wednesday' },
    { n: 4, label: 'Thursday' }, { n: 5, label: 'Friday' }, { n: 6, label: 'Saturday' }
  ];

  /**
   * Grid columns for the selected class: its saved structure (periods, breaks, lunch),
   * or a plain P1..P8 fallback until the principal sets one.
   */
  protected readonly columns = computed<PeriodScheduleItem[]>(() => {
    const s = this.schedule();
    if (s.length) return s;
    return Array.from({ length: DEFAULT_PERIODS }, (_, i) => ({
      kind: 'Period' as PeriodKind, label: `P${i + 1}`, period_no: i + 1, start_time: '', end_time: ''
    }));
  });
  protected readonly hasSchedule = computed(() => this.schedule().length > 0);

  // ---- Result popup ----
  protected readonly result = signal<ResultDialog | null>(null);
  protected closeResult(): void { this.result.set(null); }

  private showResult(kind: ResultDialog['kind'], title: string, message: string, lines: string[] = []): void {
    this.result.set({ kind, title, message, lines });
  }

  /** Server messages use "headline|line1|line2" for lists (e.g. teacher clashes). */
  private showError(title: string, err: unknown): void {
    const http = err as HttpErrorResponse;
    const text: string = http?.error?.resultCodeDescription ?? 'Something went wrong. Please try again.';
    const [head, ...lines] = text.split('|');
    this.showResult('error', http?.status === 409 ? 'Teacher already booked' : title, head, lines);
  }

  // ---- Slot editor state ----
  protected readonly editorOpen = signal(false);
  protected readonly editDay = signal(0);
  protected readonly editCol = signal<PeriodScheduleItem | null>(null);
  protected editSlotId: number | null = null;
  protected formSubjectId = 0;
  protected readonly formTeacherId = signal(0);
  protected formRoom = '';
  protected readonly busy = signal(false);

  // ---- Teacher schedules (cached) + popup ----
  private readonly teacherCache = signal<Record<number, TeacherSchedule>>({});
  protected readonly teacherPopup = signal<TeacherSchedule | null>(null);
  protected readonly teacherPopupLoading = signal(false);

  /** Teacher chosen on the "Teacher-wise" tab. */
  protected teacherViewId = 0;
  protected readonly teacherView = signal<TeacherSchedule | null>(null);
  protected readonly teacherViewLoading = signal(false);

  /** The teacher currently picked in the slot editor, once loaded. */
  protected readonly pickedTeacher = computed(() => this.teacherCache()[this.formTeacherId()] ?? null);

  /** Where the picked teacher is ALREADY teaching at the time of the slot being edited. */
  protected readonly clashes = computed<string[]>(() => {
    const t = this.pickedTeacher();
    const col = this.editCol();
    if (!t || !col) return [];
    const day = this.editDay();
    const sec = this.sectionId || 0;
    return t.items
      .filter((o) => o.day_of_week === day)
      .filter((o) => !(o.class_id === this.classId && (o.section_id ?? 0) === sec && o.period_no === col.period_no))
      .filter((o) => {
        if (col.start_time && col.end_time && o.start_time && o.end_time) {
          return o.start_time < col.end_time && col.start_time < o.end_time;
        }
        return o.period_no === col.period_no;
      })
      .map((o) => this.describeTeacherSlot(o.class_name, o.section_name, o.start_time, o.end_time, o.period_no, o.subject_name));
  });

  constructor() {
    this.academic.listClasses().subscribe((c) => this.classes.set(c));
    this.academic.listSubjects().subscribe((s) => this.subjects.set(s.filter((x) => x.is_active)));
    if (this.canManage) this.api.teachers().subscribe((t) => this.teachers.set(t));
  }

  // ---------------------------------------------------------------- class tab
  protected onClassChange(): void {
    this.sectionId = 0;
    this.sections.set([]);
    this.slots.set([]);
    this.schedule.set([]);
    if (this.classId) {
      this.academic.listSections(this.classId).subscribe((s) => this.sections.set(s));
      this.loadSchedule();
      this.loadGrid();
    }
  }

  protected onSectionChange(): void { this.loadGrid(); }

  private loadSchedule(): void {
    const id = this.classId;
    this.api.schedule(id).subscribe((s) => { if (id === this.classId) this.schedule.set(s); });
  }

  protected loadGrid(): void {
    if (!this.classId) return;
    this.loading.set(true);
    this.api.list(this.classId, this.sectionId || undefined).subscribe({
      next: (s) => { this.slots.set(s); this.loading.set(false); },
      error: () => this.loading.set(false)
    });
  }

  /** Find the slot at a given day+period number (or undefined). */
  protected slotAt(day: number, periodNo: number | null | undefined): TimetableSlot | undefined {
    if (periodNo == null) return undefined;
    return this.slots().find((s) => s.day_of_week === day && s.period_no === periodNo);
  }

  protected colTime(c: PeriodScheduleItem): string {
    return c.start_time && c.end_time ? `${c.start_time}–${c.end_time}` : '';
  }

  protected className(): string {
    return this.classes().find((c) => c.class_id === this.classId)?.name ?? '';
  }

  protected dayLabel(n: number): string { return this.days.find((d) => d.n === n)?.label ?? ''; }

  // ------------------------------------------------------------- slot editor
  protected openEditor(day: number, col: PeriodScheduleItem): void {
    if (!this.canManage || !this.classId || col.kind !== 'Period') return;
    const existing = this.slotAt(day, col.period_no);
    this.editDay.set(day);
    this.editCol.set(col);
    this.editSlotId = existing?.slot_id ?? null;
    this.formSubjectId = existing?.subject_id ?? 0;
    this.formTeacherId.set(existing?.teacher_id ?? 0);
    this.formRoom = existing?.room ?? '';
    if (existing?.teacher_id) this.ensureTeacher(existing.teacher_id);
    this.editorOpen.set(true);
  }

  protected closeEditor(): void { this.editorOpen.set(false); }

  protected onTeacherPick(id: number): void {
    const tid = Number(id);
    this.formTeacherId.set(tid);
    if (tid) this.ensureTeacher(tid);
  }

  /** Load (once) a teacher's full schedule so clashes can be shown before saving. */
  private ensureTeacher(id: number, force = false): void {
    if (!force && this.teacherCache()[id]) return;
    this.api.teacherSchedule(id).subscribe((t) => {
      if (t) this.teacherCache.update((c) => ({ ...c, [id]: t }));
    });
  }

  protected saveSlot(): void {
    const col = this.editCol();
    if (!col || this.busy()) return;
    this.busy.set(true);
    const day = this.editDay();
    const teacherId = this.formTeacherId();
    this.api.save({
      SlotId: this.editSlotId,
      ClassId: this.classId,
      SectionId: this.sectionId || null,
      DayOfWeek: day,
      PeriodNo: col.period_no ?? 0,
      StartTime: col.start_time || null,
      EndTime: col.end_time || null,
      SubjectId: this.formSubjectId || null,
      TeacherId: teacherId || null,
      Room: this.formRoom || null
    }).subscribe({
      next: (res) => {
        this.busy.set(false);
        if (res.isSuccess) {
          const wasEdit = !!this.editSlotId;
          const subj = this.subjects().find((s) => s.subject_id === this.formSubjectId)?.name;
          const tch = this.teachers().find((t) => t.user_id === teacherId)?.full_name;
          this.closeEditor();
          if (teacherId) this.ensureTeacher(teacherId, true);
          this.loadGrid();
          this.showResult('success', wasEdit ? 'Period updated' : 'Period added',
            `${subj ?? 'Period'}${tch ? ' with ' + tch : ''} is set for ${this.dayLabel(day)} · ${col.label}${this.colTime(col) ? ' (' + this.colTime(col) + ')' : ''}.`);
        } else {
          this.showResult('error', 'Could not save', res.resultCodeDescription ?? 'Please try again.');
        }
      },
      error: (err) => { this.busy.set(false); this.showError('Could not save', err); }
    });
  }

  protected deleteSlot(): void {
    if (!this.editSlotId || this.busy()) return;
    if (!confirm('Clear this period?')) return;
    this.busy.set(true);
    const tid = this.formTeacherId();
    this.api.delete(this.editSlotId).subscribe({
      next: (res) => {
        this.busy.set(false);
        if (res.isSuccess) {
          this.closeEditor();
          if (tid) this.ensureTeacher(tid, true);
          this.loadGrid();
          this.showResult('success', 'Period cleared', 'The period is now empty.');
        } else {
          this.showResult('error', 'Could not clear', res.resultCodeDescription ?? 'Please try again.');
        }
      },
      error: (err) => { this.busy.set(false); this.showError('Could not clear', err); }
    });
  }

  // --------------------------------------------------------- teacher schedule
  /** Open the "where does this teacher teach" popup. */
  protected openTeacher(id: number | null | undefined, ev?: Event): void {
    ev?.stopPropagation();
    if (!id) return;
    this.teacherPopup.set(null);
    this.teacherPopupLoading.set(true);
    this.api.teacherSchedule(id).subscribe({
      next: (t) => { this.teacherPopup.set(t); this.teacherPopupLoading.set(false); },
      error: () => this.teacherPopupLoading.set(false)
    });
  }
  protected closeTeacherPopup(): void { this.teacherPopup.set(null); this.teacherPopupLoading.set(false); }

  protected loadTeacherView(): void {
    if (!this.teacherViewId) { this.teacherView.set(null); return; }
    this.teacherViewLoading.set(true);
    this.api.teacherSchedule(this.teacherViewId).subscribe({
      next: (t) => { this.teacherView.set(t); this.teacherViewLoading.set(false); },
      error: () => this.teacherViewLoading.set(false)
    });
  }

  /** A teacher's slots grouped by weekday (empty days omitted). */
  protected byDay(t: TeacherSchedule): { label: string; items: TeacherSchedule['items'] }[] {
    return this.days
      .map((d) => ({ label: d.label, items: t.items.filter((i) => i.day_of_week === d.n) }))
      .filter((g) => g.items.length > 0);
  }

  protected describeTeacherSlot(cls: string | null, sec: string | null, start: string | null,
                                end: string | null, periodNo: number, subject: string | null): string {
    const where = `Class ${cls ?? '?'}${sec ? ' ' + sec : ' (all sections)'}`;
    const when = start && end ? `${start}–${end}` : `P${periodNo}`;
    return `${where} · ${when}${subject ? ' · ' + subject : ''}`;
  }

  // ------------------------------------------------- period structure editor
  protected readonly scheduleOpen = signal(false);
  protected readonly rows = signal<ScheduleRow[]>([]);
  protected copyFromClassId = 0;
  protected readonly scheduleBusy = signal(false);
  protected readonly scheduleError = signal('');

  protected openScheduleEditor(): void {
    if (!this.canManage || !this.classId) return;
    this.scheduleError.set('');
    this.copyFromClassId = 0;
    const cur = this.schedule();
    this.rows.set(cur.length
      ? cur.map((c) => ({ kind: c.kind, label: c.label, start_time: c.start_time, end_time: c.end_time }))
      : this.sampleRows());
    this.scheduleOpen.set(true);
  }

  protected closeScheduleEditor(): void { this.scheduleOpen.set(false); }

  /** 8:00 start, 40-min periods, short break after P2, lunch after P5. */
  private sampleRows(): ScheduleRow[] {
    const out: ScheduleRow[] = [];
    let t = '08:00';
    const push = (kind: PeriodKind, label: string, mins: number) => {
      const end = this.addMinutes(t, mins);
      out.push({ kind, label, start_time: t, end_time: end });
      t = end;
    };
    for (let p = 1; p <= 7; p++) {
      push('Period', `P${p}`, 40);
      if (p === 2) push('Break', 'Short Break', 15);
      if (p === 5) push('Lunch', 'Lunch', 30);
    }
    return out;
  }

  protected loadSample(): void { this.rows.set(this.sampleRows()); }

  /** Copy another class's structure into the editor (nothing is saved until Save). */
  protected copyFromClass(): void {
    if (!this.copyFromClassId) return;
    this.api.schedule(this.copyFromClassId).subscribe((s) => {
      if (!s.length) { this.scheduleError.set('That class has no period structure set yet.'); return; }
      this.scheduleError.set('');
      this.rows.set(s.map((c) => ({ kind: c.kind, label: c.label, start_time: c.start_time, end_time: c.end_time })));
    });
  }

  protected addRow(kind: PeriodKind): void {
    const list = this.rows();
    const last = list[list.length - 1];
    const start = last?.end_time || '08:00';
    const mins = kind === 'Period' ? 40 : kind === 'Lunch' ? 30 : 15;
    this.rows.set([...list, { kind, label: kind === 'Period' ? '' : (kind === 'Lunch' ? 'Lunch' : 'Short Break'),
      start_time: start, end_time: this.addMinutes(start, mins) }]);
  }

  protected removeRow(i: number): void { this.rows.update((l) => l.filter((_, idx) => idx !== i)); }

  protected moveRow(i: number, dir: -1 | 1): void {
    const j = i + dir;
    this.rows.update((l) => {
      if (j < 0 || j >= l.length) return l;
      const c = [...l];
      [c[i], c[j]] = [c[j], c[i]];
      return c;
    });
  }

  protected updateRow(i: number, patch: Partial<ScheduleRow>): void {
    this.rows.update((l) => l.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));
  }

  /** Display number of a Period row ("Period 3"); breaks/lunch return 0. */
  protected periodNumber(i: number): number {
    const r = this.rows();
    if (r[i]?.kind !== 'Period') return 0;
    return r.slice(0, i + 1).filter((x) => x.kind === 'Period').length;
  }

  protected readonly periodCount = computed(() => this.rows().filter((r) => r.kind === 'Period').length);

  private addMinutes(hhmm: string, mins: number): string {
    const [h, m] = hhmm.split(':').map(Number);
    const total = Math.min(23 * 60 + 59, h * 60 + m + mins);
    return `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
  }

  /** Client-side checks so the principal gets a clear message before the server round-trip. */
  private validateRows(): string {
    const r = this.rows();
    if (!r.some((x) => x.kind === 'Period')) return 'Add at least one period.';
    let prevEnd = '';
    for (let i = 0; i < r.length; i++) {
      const name = r[i].kind === 'Period' ? `Period ${this.periodNumber(i)}` : (r[i].label || r[i].kind);
      if (!r[i].start_time || !r[i].end_time) return `Set start and end time for ${name}.`;
      if (r[i].end_time <= r[i].start_time) return `${name}: end time must be after start time.`;
      if (prevEnd && r[i].start_time < prevEnd) return `${name} starts before the previous row ends.`;
      prevEnd = r[i].end_time;
    }
    return '';
  }

  protected saveSchedule(): void {
    if (this.scheduleBusy()) return;
    const problem = this.validateRows();
    if (problem) { this.scheduleError.set(problem); return; }
    this.scheduleError.set('');
    const cls = this.className();
    const items: PeriodScheduleItem[] = this.rows().map((r, i) => ({
      kind: r.kind,
      label: r.kind === 'Period' ? `P${this.periodNumber(i)}` : (r.label.trim() || r.kind),
      start_time: r.start_time,
      end_time: r.end_time
    }));
    this.scheduleBusy.set(true);
    this.api.saveSchedule(this.classId, items).subscribe({
      next: (res) => {
        this.scheduleBusy.set(false);
        if (res.isSuccess) {
          this.closeScheduleEditor();
          this.loadSchedule();
          this.loadGrid();
          const removed = res.data?.removed_slots ?? 0;
          this.showResult('success', 'Period structure saved',
            `Class ${cls} now has ${res.data?.periods ?? this.periodCount()} periods.`,
            removed ? [`${removed} timetable entr${removed === 1 ? 'y' : 'ies'} of removed periods ${removed === 1 ? 'was' : 'were'} cleared.`] : []);
        } else {
          this.scheduleError.set(res.resultCodeDescription ?? 'Could not save.');
        }
      },
      error: (err: HttpErrorResponse) => {
        this.scheduleBusy.set(false);
        this.scheduleError.set(err?.error?.resultCodeDescription ?? 'Could not save.');
      }
    });
  }
}
