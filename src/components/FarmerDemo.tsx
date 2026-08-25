import { useEffect, useRef, useState } from 'react'
import {
  Camera,
  CheckCircle2,
  CloudSun,
  MapPinned,
  Route,
  ScanLine,
  Sprout,
  WalletCards,
  WifiOff,
} from 'lucide-react'
import { demoViews, sampleMarkets, type DemoView } from '../data/demo'

type ScanState = 'idle' | 'scanning' | 'result'

export function FarmerDemo() {
  const [activeView, setActiveView] = useState<DemoView>('today')
  const [scanState, setScanState] = useState<ScanState>('idle')
  const timerRef = useRef<number | null>(null)

  useEffect(
    () => () => {
      if (timerRef.current) window.clearTimeout(timerRef.current)
    },
    [],
  )

  const runSampleScan = () => {
    if (timerRef.current) window.clearTimeout(timerRef.current)
    setScanState('scanning')
    timerRef.current = window.setTimeout(() => setScanState('result'), 750)
  }

  return (
    <section className="demo-section" id="demo" aria-labelledby="demo-heading">
      <div className="section-kicker">Clickable product preview</div>
      <div className="demo-heading-row">
        <div>
          <h2 id="demo-heading">A farmer view that starts with today.</h2>
          <p>Four useful decisions, kept close. All values below are sample data for the hackathon demo.</p>
        </div>
        <div className="offline-badge"><WifiOff size={17} aria-hidden="true" /> Offline-ready demo</div>
      </div>

      <div className="farmer-demo">
        <aside className="demo-sidebar" aria-label="Farmer summary">
          <div className="farmer-mark"><Sprout size={24} aria-hidden="true" /></div>
          <p className="demo-overline">My farm</p>
          <h3>Hammanskraal plot</h3>
          <p>3 crop zones · 480 m²</p>
          <div className="sync-note">
            <span className="status-dot" />
            Last saved on this phone
          </div>
        </aside>

        <div className="demo-workspace">
          <div className="demo-tabs" role="tablist" aria-label="Demo views">
            {demoViews.map((view) => (
              <button
                aria-controls={`panel-${view.id}`}
                aria-selected={activeView === view.id}
                className="demo-tab"
                id={`tab-${view.id}`}
                key={view.id}
                onClick={() => setActiveView(view.id)}
                role="tab"
                type="button"
              >
                {view.label}
              </button>
            ))}
          </div>

          <div
            aria-labelledby={`tab-${activeView}`}
            className="demo-panel"
            id={`panel-${activeView}`}
            role="tabpanel"
            tabIndex={0}
          >
            {activeView === 'today' && (
              <div className="today-grid">
                <article className="demo-card demo-card--lead">
                  <div className="card-icon"><Camera size={22} aria-hidden="true" /></div>
                  <p className="demo-overline">Next field task</p>
                  <h3>Check the maize zone</h3>
                  <p>Photograph five plants. Start with the ones showing yellow or spotted leaves.</p>
                  <button className="text-action" onClick={() => setActiveView('crop')} type="button">
                    Open crop check <ScanLine size={17} aria-hidden="true" />
                  </button>
                </article>
                <article className="demo-card">
                  <CloudSun size={23} aria-hidden="true" />
                  <p className="demo-overline">Sample forecast</p>
                  <h3>27°C today</h3>
                  <p>Rain risk rises on Thursday.</p>
                </article>
                <article className="demo-card">
                  <WalletCards size={23} aria-hidden="true" />
                  <p className="demo-overline">Sample margin</p>
                  <h3>R1,840</h3>
                  <p>Projected after recorded input costs.</p>
                </article>
              </div>
            )}

            {activeView === 'crop' && (
              <div className="scan-layout">
                <div className={`scan-frame scan-frame--${scanState}`}>
                  {scanState === 'result' ? <CheckCircle2 size={54} aria-hidden="true" /> : <ScanLine size={54} aria-hidden="true" />}
                  <span>{scanState === 'scanning' ? 'Checking sample image…' : 'Five clear plant photos work best'}</span>
                </div>
                <div className="scan-copy">
                  <p className="demo-overline">On-device crop check</p>
                  <h3>{scanState === 'result' ? 'Possible leaf spot' : 'Check a crop photo'}</h3>
                  {scanState === 'result' ? (
                    <>
                      <p className="confidence">Sample result · 78% confidence</p>
                      <p>Check five nearby plants. If three show the same spots, ask an extension worker before applying treatment.</p>
                    </>
                  ) : (
                    <p>This interaction demonstrates the intended camera flow. No image leaves the browser and no model runs in this frontend.</p>
                  )}
                  <button className="primary-button primary-button--small" disabled={scanState === 'scanning'} onClick={runSampleScan} type="button">
                    {scanState === 'result' ? 'Run again' : scanState === 'scanning' ? 'Checking…' : 'Run sample check'}
                  </button>
                </div>
              </div>
            )}

            {activeView === 'markets' && (
              <div className="market-layout">
                <div className="mini-map" aria-label="Stylised sample market map">
                  <span className="map-road map-road--one" />
                  <span className="map-road map-road--two" />
                  <MapPinned className="map-pin map-pin--farm" size={30} aria-hidden="true" />
                  <MapPinned className="map-pin map-pin--market" size={30} aria-hidden="true" />
                </div>
                <div>
                  <p className="demo-overline">Sample maize prices</p>
                  <h3>Compare the trip, not only the price.</h3>
                  <div className="market-list">
                    {sampleMarkets.map((market) => (
                      <div className="market-row" key={market.name}>
                        <div><strong>{market.name}</strong><span><Route size={15} aria-hidden="true" /> {market.distance}</span></div>
                        <span>{market.price}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            )}

            {activeView === 'costs' && (
              <div className="cost-layout">
                <div className="cost-summary">
                  <p className="demo-overline">Sample season estimate</p>
                  <strong>R1,840</strong>
                  <span>projected margin</span>
                </div>
                <div className="cost-lines">
                  <div><span>Expected sales</span><strong>R4,200</strong></div>
                  <div><span>Seed and fertiliser</span><strong>− R1,460</strong></div>
                  <div><span>Transport and packaging</span><strong>− R900</strong></div>
                  <div className="cost-line-total"><span>What remains</span><strong>R1,840</strong></div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </section>
  )
}
