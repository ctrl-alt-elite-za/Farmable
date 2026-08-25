export type DemoView = 'today' | 'crop' | 'markets' | 'costs'

export const demoViews: Array<{ id: DemoView; label: string }> = [
  { id: 'today', label: 'Today' },
  { id: 'crop', label: 'Crop check' },
  { id: 'markets', label: 'Markets' },
  { id: 'costs', label: 'Costs' },
]

export const sampleMarkets = [
  { name: 'Tshwane Fresh Produce Market', distance: '18 km', price: 'R7.20/kg' },
  { name: 'Hammanskraal traders', distance: '4 km', price: 'R6.60/kg' },
  { name: 'Soshanguve Saturday market', distance: '11 km', price: 'R7.00/kg' },
]
