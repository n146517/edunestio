import { Component, computed, inject, signal } from '@angular/core';
import { TimetableService } from '../../core/services/timetable.service';
import { TimetableSlot } from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

/** Student self-service: my class's weekly timetable. */
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

  protected readonly days = [
    { n: 1, label: 'Monday' }, { n: 2, label: 'Tuesday' }, { n: 3, label: 'Wednesday' },
    { n: 4, label: 'Thursday' }, { n: 5, label: 'Friday' }, { n: 6, label: 'Saturday' }
  ];

  /** Period numbers that actually appear in the data (so the grid isn't over-wide). */
  protected readonly periods = computed(() => {
    const set = new Set(this.slots().map((s) => s.period_no));
    const arr = [...set].sort((a, b) => a - b);
    return arr.length ? arr : [1, 2, 3, 4, 5, 6];
  });

  constructor() {
    this.api.mine().subscribe({
      next: (s) => { this.slots.set(s); this.state.set('success'); },
      error: () => this.state.set('error')
    });
  }

  protected slotAt(day: number, period: number): TimetableSlot | undefined {
    return this.slots().find((s) => s.day_of_week === day && s.period_no === period);
  }
}
