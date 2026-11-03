import { Injectable, computed, inject, signal } from '@angular/core';
import { AcademicService } from '../services/academic.service';
import { AuthStore } from '../auth/auth.store';
import { AcademicYear } from '../models/api.models';

const STORAGE_KEY = 'edunest.activeYear';

/**
 * App-wide "active academic year". A single selection (persisted per session) that
 * screens use as their default year filter, so choosing e.g. 2025-26 in the header
 * scopes the whole portal to that year. 0 means "All years".
 */
@Injectable({ providedIn: 'root' })
export class AcademicYearStore {
  private readonly academic = inject(AcademicService);
  private readonly auth = inject(AuthStore);

  private readonly _years = signal<AcademicYear[]>([]);
  private readonly _selectedId = signal<number>(this.restore());
  private _loaded = false;

  readonly years = this._years.asReadonly();
  readonly selectedId = this._selectedId.asReadonly();

  /** The selected year object, or null for "All years". */
  readonly selected = computed(() =>
    this._years().find((y) => y.academic_year_id === this._selectedId()) ?? null
  );

  /** Load the tenant's years once; default the selection to the current year. */
  load(): void {
    if (this._loaded || !this.auth.isAuthenticated()) return;
    this._loaded = true;
    this.academic.listYears().subscribe((ys) => {
      this._years.set(ys);
      // If nothing valid is selected yet, prefer the flagged current year.
      const stillValid = ys.some((y) => y.academic_year_id === this._selectedId());
      if (this._selectedId() === 0 && !this.hasStoredChoice()) {
        const current = ys.find((y) => y.is_current);
        if (current) this.select(current.academic_year_id);
      } else if (this._selectedId() !== 0 && !stillValid) {
        this.select(0);
      }
    });
  }

  select(id: number): void {
    this._selectedId.set(id);
    sessionStorage.setItem(STORAGE_KEY, String(id));
  }

  /** The id to send to APIs as a filter (undefined when "All years"). */
  filterId(): number | undefined {
    const id = this._selectedId();
    return id > 0 ? id : undefined;
  }

  private restore(): number {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    const n = raw ? Number(raw) : NaN;
    return Number.isFinite(n) && n >= 0 ? n : 0;
  }

  private hasStoredChoice(): boolean {
    return sessionStorage.getItem(STORAGE_KEY) !== null;
  }
}
