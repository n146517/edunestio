import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe } from '@angular/common';
import { AssignmentService } from '../../core/services/assignment.service';
import { NotificationService } from '../../core/services/notification.service';
import { StudentAssignment } from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

/** Student self-service: my assignments — view, submit, see grade/feedback. */
@Component({
  selector: 'app-my-assignments',
  imports: [FormsModule, DatePipe],
  templateUrl: './my-assignments.component.html',
  styleUrl: './assignments.component.scss'
})
export class MyAssignmentsComponent {
  private readonly api = inject(AssignmentService);
  private readonly notify = inject(NotificationService);

  protected readonly state = signal<LoadState>('loading');
  protected readonly items = signal<StudentAssignment[]>([]);

  protected readonly pendingCount = computed(() =>
    this.items().filter((a) => !a.submission_id).length
  );

  // Submit dialog.
  protected readonly submitOpen = signal(false);
  protected readonly submitFor = signal<StudentAssignment | null>(null);
  protected content = '';
  protected readonly busy = signal(false);

  constructor() { this.load(); }

  protected load(): void {
    this.state.set('loading');
    this.api.mine().subscribe({
      next: (a) => { this.items.set(a); this.state.set('success'); },
      error: () => this.state.set('error')
    });
  }

  protected openSubmit(a: StudentAssignment): void {
    if (a.my_status === 'Graded') { this.notify.info('This assignment is already graded.'); return; }
    this.submitFor.set(a);
    this.content = a.my_content ?? '';
    this.submitOpen.set(true);
  }

  protected closeSubmit(): void { this.submitOpen.set(false); }

  protected submit(): void {
    const a = this.submitFor();
    if (!a || this.busy()) return;
    if (!this.content.trim()) { this.notify.info('Write your answer / note before submitting.'); return; }
    this.busy.set(true);
    this.api.submit(a.assignment_id, this.content.trim()).subscribe({
      next: (res) => {
        this.busy.set(false);
        if (res.isSuccess) { this.notify.success('Submitted.'); this.closeSubmit(); this.load(); }
        else this.notify.error(res.resultCodeDescription ?? 'Could not submit.');
      },
      error: () => this.busy.set(false)
    });
  }

  protected statusBadge(a: StudentAssignment): string {
    if (a.my_status === 'Graded') return 'pill pill--graded';
    if (a.my_status === 'Submitted') return 'pill pill--sub';
    return 'pill pill--none';
  }
  protected statusText(a: StudentAssignment): string {
    if (a.my_status === 'Graded') return 'Graded';
    if (a.my_status === 'Submitted') return 'Submitted';
    return 'Pending';
  }
}
