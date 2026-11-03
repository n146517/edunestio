import { Component, inject, signal } from '@angular/core';
import { SettingsService } from '../../core/services/settings.service';
import { AuthStore } from '../../core/auth/auth.store';
import { NotificationService } from '../../core/services/notification.service';
import { TenantSettings } from '../../core/models/api.models';

type LoadState = 'loading' | 'success' | 'error';

/** School settings. Currently: attendance mode (Daily vs Subject-wise). */
@Component({
  selector: 'app-settings',
  imports: [],
  templateUrl: './settings.component.html',
  styleUrl: './settings.component.scss'
})
export class SettingsComponent {
  private readonly api = inject(SettingsService);
  private readonly notify = inject(NotificationService);
  private readonly store = inject(AuthStore);

  protected readonly state = signal<LoadState>('loading');
  protected readonly settings = signal<TenantSettings | null>(null);
  protected readonly saving = signal(false);

  protected readonly canManage = this.store.hasPermission('settings.manage');

  constructor() { this.load(); }

  private load(): void {
    this.state.set('loading');
    this.api.get().subscribe({
      next: (s) => { this.settings.set(s); this.state.set('success'); },
      error: () => this.state.set('error')
    });
  }

  protected setMode(mode: 'Daily' | 'Subject'): void {
    const s = this.settings();
    if (!s || !this.canManage || this.saving() || s.attendance_mode === mode) return;
    this.saving.set(true);
    this.api.setAttendanceMode(mode).subscribe({
      next: (res) => {
        this.saving.set(false);
        if (res.isSuccess) {
          this.settings.update((cur) => cur ? { ...cur, attendance_mode: mode } : cur);
          this.notify.success('Attendance mode updated.');
        } else {
          this.notify.error(res.resultCodeDescription ?? 'Could not update.');
        }
      },
      error: () => this.saving.set(false)
    });
  }
}
