import { Component, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AttendanceService } from '../../core/services/attendance.service';
import { AcademicService } from '../../core/services/academic.service';
import { AuthStore } from '../../core/auth/auth.store';
import { AcademicYear, AttendanceHistoryRow } from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error' | 'nostudent';

/** Student self-service: my own attendance history + summary, filterable by academic year. */
@Component({
  selector: 'app-my-attendance',
  imports: [DatePipe, FormsModule],
  templateUrl: './my-attendance.component.html',
  styleUrl: './my-attendance.component.scss'
})
export class MyAttendanceComponent {
  private readonly api = inject(AttendanceService);
  private readonly academic = inject(AcademicService);
  private readonly store = inject(AuthStore);

  protected readonly state = signal<LoadState>('loading');
  /** All fetched rows (across years). */
  private readonly allRows = signal<AttendanceHistoryRow[]>([]);
  protected readonly years = signal<AcademicYear[]>([]);
  /** Selected academic year id; 0 = all years. */
  protected yearId = 0;

  /** Rows filtered to the selected academic year's date range. */
  protected readonly rows = computed(() => {
    const all = this.allRows();
    const y = this.years().find((x) => x.academic_year_id === this.yearId);
    if (!y) return all; // 0 / All years
    const from = y.start_date?.substring(0, 10) ?? '';
    const to = y.end_date?.substring(0, 10) ?? '';
    return all.filter((r) => {
      const d = r.attend_date.substring(0, 10);
      return (!from || d >= from) && (!to || d <= to);
    });
  });

  protected readonly summary = computed(() => {
    const rows = this.rows();
    const by: Record<string, number> = { Present: 0, Absent: 0, Late: 0, Leave: 0 };
    for (const r of rows) by[r.status] = (by[r.status] ?? 0) + 1;
    const total = rows.length;
    const pct = total ? Math.round((by['Present'] / total) * 100) : 0;
    return { total, present: by['Present'], absent: by['Absent'], late: by['Late'], leave: by['Leave'], pct };
  });

  constructor() {
    const sid = this.store.studentId();
    if (!sid) { this.state.set('nostudent'); return; }
    // Years for the filter; default to the current year if there is one.
    this.academic.listYears().subscribe((ys) => {
      this.years.set(ys);
      const current = ys.find((y) => y.is_current);
      if (current) this.yearId = current.academic_year_id;
    });
    this.load(sid);
  }

  private load(sid: number): void {
    this.state.set('loading');
    // Pull a wide window so multiple years of history are available for filtering.
    this.api.history(sid, 1000).subscribe({
      next: (r) => { this.allRows.set(r); this.state.set('success'); },
      error: () => this.state.set('error')
    });
  }

  protected attendClass(status: string): string {
    switch (status) {
      case 'Present': return 'pill pill--pass';
      case 'Absent': return 'pill pill--fail';
      case 'Late': return 'badge badge--late';
      case 'Leave': return 'badge badge--leave';
      default: return 'pill';
    }
  }
}
