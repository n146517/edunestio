import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import { ApiResponse, ItemsData, Teacher, TimetableSlot, TimetableSlotUpsert } from '../models/api.models';

/** Typed client for the Timetable module. */
@Injectable({ providedIn: 'root' })
export class TimetableService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/timetable`;

  /** Teachers of the school (for the slot teacher dropdown). */
  teachers(): Observable<Teacher[]> {
    return this.http
      .get<ApiResponse<ItemsData<Teacher>>>(`${this.base}/teachers`)
      .pipe(map((r) => r.data?.items ?? []));
  }

  /** Slots for a class (optionally a section). */
  list(classId: number, sectionId?: number): Observable<TimetableSlot[]> {
    let p = new HttpParams().set('classId', classId);
    if (sectionId) p = p.set('sectionId', sectionId);
    return this.http
      .get<ApiResponse<ItemsData<TimetableSlot>>>(this.base, { params: p })
      .pipe(map((r) => r.data?.items ?? []));
  }

  /** The signed-in student's own class timetable. */
  mine(): Observable<TimetableSlot[]> {
    return this.http
      .get<ApiResponse<ItemsData<TimetableSlot>>>(`${this.base}/mine`)
      .pipe(map((r) => r.data?.items ?? []));
  }

  save(body: TimetableSlotUpsert): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(this.base, body);
  }

  delete(slotId: number): Observable<ApiResponse> {
    return this.http.delete<ApiResponse>(`${this.base}/${slotId}`);
  }
}
