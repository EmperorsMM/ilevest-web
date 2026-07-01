// Typed access to the location reference. The data lives in
// ../data/ilevest_location_data.json — add a new state by appending to that
// file; no code change here is needed. Lagos/Ogun subdivide into LGAs, FCT into
// Area Councils (never call those LGAs), and AMAC additionally carries common
// districts because Abuja property is referenced by district.
import data from "../data/ilevest_location_data.json";

export type LocState = {
  code: string;
  name: string;
  subdivision_label: string;
  subdivisions: string[];
  amac_common_districts?: string[];
};

export const STATES: LocState[] = (data.states as LocState[]);

export function findState(name: string): LocState | undefined {
  return STATES.find((s) => s.name === name);
}

export function stateCode(stateName: string): string | null {
  return findState(stateName)?.code ?? null;
}

export function subdivisionLabel(stateName: string): string {
  return findState(stateName)?.subdivision_label ?? "LGA / Area Council";
}

export function subdivisionsFor(stateName: string): string[] {
  return findState(stateName)?.subdivisions ?? [];
}

export function districtsFor(stateName: string): string[] {
  return findState(stateName)?.amac_common_districts ?? [];
}

// District field applies where a state carries district data (AMAC today) and
// the chosen subdivision is the one that uses districts.
export function usesDistricts(stateName: string, subdivision: string): boolean {
  return districtsFor(stateName).length > 0 && subdivision.includes("AMAC");
}
