import { Component, computed, inject, signal } from '@angular/core';
import { TimetableService } from '../../core/services/timetable.service';
import { PeriodKind, PeriodScheduleItem, TimetableSlot } from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

/** Student self-service: my class's weekly timetable (with its break / lunch structure). */
@Component({
  selector: 'app-my-timetable',
  imports: [],
  templateUrl: './my-timetable.component.html',
  styleUrl: './timetable.component.scss'
})
export class MyTimetableComponent {
  private readonly api = inject(TimetableService);

  protected readonly state = signal<LoadState>('loading');
  protected readonly slots = signal<TimetableSlot[]>([]);
  private readonly schedule = signal<PeriodScheduleItem[]>([]);

  protected readonly days = [
    { n: 1, label: 'Monday' }, { n: 2, label: 'Tuesday' }, { n: 3, label: 'Wednesday' },
    { n: 4, label: 'Thursday' }, { n: 5, label: 'Friday' }, { n: 6, label: 'Saturday' }
  ];

  /**
   * Columns: the class's saved structure (periods, breaks, lunch); if none was set,
   * only the period numbers that actually appear in the data.
   */
  protected readonly columns = computed<PeriodScheduleItem[]>(() => {
    const s = this.schedule();
    if (s.length) return s;
    const nums = [...new Set(this.slots().map((x) => x.period_no))].sort((a, b) => a - b);
    const list = nums.length ? nums : [1, 2, 3, 4, 5, 6];
    return list.map((n) => ({
      kind: 'Period' as PeriodKind, label: `P${n}`, period_no: n, start_time: '', end_time: ''
    }));
  });

  constructor() {
    this.api.mine().subscribe({
      next: (t) => { this.slots.set(t.items); this.schedule.set(t.schedule); this.state.set('success'); },
      error: () => this.state.set('error')
    });
  }

  protected slotAt(day: number, periodNo: number | null | undefined): TimetableSlot | undefined {
    if (periodNo == null) return undefined;
    return this.slots().find((s) => s.day_of_week === day && s.period_no === periodNo);
  }

  protected colTime(c: PeriodScheduleItem): string {
    return c.start_time && c.end_time ? `${c.start_time}–${c.end_time}` : '';
  }
}
