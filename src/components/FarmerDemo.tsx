import { useEffect, useRef, useState, type KeyboardEvent } from 'react'
import {
  CheckCircle2,
  CloudSun,
  MapPinned,
  Route,
  Save,
  ScanLine,
  Undo2,
  WalletCards,
} from 'lucide-react'
import { demoViews, sampleMarkets, type DemoView } from '../data/demo'
import maizeFieldPhoto from '../assets/maize-field-placeholder.webp'
import maizeLeafPhoto from '../assets/maize-leaf-placeholder.webp'

type ScanState = 'idle' | 'scanning' | 'result'

const expectedSales = 4200
const baseInputCosts = 1460
const transportAndPackaging = 900
const demoCostIncrement = 120

const currency = new Intl.NumberFormat('en-ZA', {
  style: 'currency',
  currency: 'ZAR',
  maximumFractionDigits: 0,
})

export function FarmerDemo() {
  const [activeView, setActiveView] = useState<DemoView>('today')
  const [scanState, setScanState] = useState<ScanState>('idle')
  const [scanSaved, setScanSaved] = useState(false)
  const [selectedMarketName, setSelectedMarketName] = useState(sampleMarkets[0].name)
  const [confirmedMarketName, setConfirmedMarketName] = useState<string | null>(null)
  const [recordedExtraCost, setRecordedExtraCost] = useState(0)
  const [statusMessage, setStatusMessage] = useState('Farmer view ready. Changes stay on this device.')
  const timerRef = useRef<number | null>(null)

  const selectedMarket = sampleMarkets.find((market) => market.name === selectedMarketName) ?? sampleMarkets[0]
  const projectedMargin = expectedSales - baseInputCosts - transportAndPackaging - recordedExtraCost

  useEffect(
    () => () => {
      if (timerRef.current) window.clearTimeout(timerRef.current)
    },
    [],
  )

  const openView = (view: DemoView) => {
    setActiveView(view)
    const label = demoViews.find((item) => item.id === view)?.label ?? view
    setStatusMessage(`${label} view opened.`)
  }

  const handleTabKeyDown = (event: KeyboardEvent<HTMLButtonElement>, index: number) => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return
    event.preventDefault()

    const direction = event.key === 'ArrowRight' ? 1 : -1
    const nextIndex = (index + direction + demoViews.length) % demoViews.length
    const nextView = demoViews[nextIndex]
    openView(nextView.id)
    window.requestAnimationFrame(() => document.getElementById(`tab-${nextView.id}`)?.focus())
  }

  const runSampleScan = () => {
    if (timerRef.current) window.clearTimeout(timerRef.current)
    setScanSaved(false)
    setScanState('scanning')
    setStatusMessage('Checking the sample crop image on this device.')

    timerRef.current = window.setTimeout(() => {
      setScanState('result')
      setStatusMessage('Sample scan complete. Possible leaf spot returned at 78% confidence.')
    }, 750)
  }

  const saveSampleScan = () => {
    setScanSaved(true)
    setStatusMessage('Sample crop check saved to this browser session.')
  }

  const selectMarket = (marketName: string) => {
    setSelectedMarketName(marketName)
    setConfirmedMarketName(null)
    setStatusMessage(`${marketName} selected for comparison.`)
  }

  const confirmMarket = () => {
    setConfirmedMarketName(selectedMarket.name)
    setStatusMessage(`${selectedMarket.name} saved as the sample selling route.`)
  }

  const addDemoCost = () => {
    setRecordedExtraCost((current) => current + demoCostIncrement)
    setStatusMessage(`${currency.format(demoCostIncrement)} added to the sample input costs.`)
  }

  const undoDemoCost = () => {
    setRecordedExtraCost((current) => Math.max(0, current - demoCostIncrement))
    setStatusMessage(`The latest ${currency.format(demoCostIncrement)} sample cost was removed.`)
  }

  return (
    <section className="demo-section" id="demo" aria-labelledby="demo-heading">
      <div className="section-kicker">Farm overview</div>
      <div className="demo-heading-row">
        <div>
          <h2 id="demo-heading">A farmer view that starts with today.</h2>
          <p>Field tasks, crop checks, market routes and costs stay together in one view.</p>
        </div>
        <div className="offline-badge">Available offline</div>
      </div>

      <div className="farmer-demo">
        <aside className="demo-sidebar" aria-label="Farmer summary">
          <p className="demo-overline">My farm</p>
          <h3>Hammanskraal plot</h3>
          <p>3 crop zones · 480 m²</p>
          <div className="sync-note">
            <span className="status-dot" />
            Changes saved in this browser
          </div>
        </aside>

        <div className="demo-workspace">
          <div className="demo-tabs" role="tablist" aria-label="Farm views">
            {demoViews.map((view, index) => (
              <button
                aria-controls="demo-panel"
                aria-selected={activeView === view.id}
                className="demo-tab"
                id={`tab-${view.id}`}
                key={view.id}
                onClick={() => openView(view.id)}
                onKeyDown={(event) => handleTabKeyDown(event, index)}
                role="tab"
                tabIndex={activeView === view.id ? 0 : -1}
                type="button"
              >
                {view.label}
              </button>
            ))}
          </div>

          <div
            aria-labelledby={`tab-${activeView}`}
            className="demo-panel"
            id="demo-panel"
            role="tabpanel"
            tabIndex={0}
          >
            {activeView === 'today' && (
              <div className="today-grid">
                <article className="demo-card demo-card--lead">
                  <img
                    alt=""
                    className="demo-farm-photo"
                    decoding="async"
                    height="1067"
                    loading="lazy"
                    src={maizeFieldPhoto}
                    width="1600"
                  />
                  <p className="demo-overline">Next field task</p>
                  <h3>Check the maize zone</h3>
                  <p>Photograph five plants. Start with the ones showing yellow or spotted leaves.</p>
                  <button className="text-action" onClick={() => openView('crop')} type="button">
                    Open crop check <ScanLine size={17} aria-hidden="true" />
                  </button>
                </article>
                <article className="demo-card demo-card--action">
                  <CloudSun size={23} aria-hidden="true" />
                  <p className="demo-overline">Sample forecast</p>
                  <h3>27°C today</h3>
                  <p>Rain risk rises on Thursday.</p>
                  <button className="text-action text-action--dark" onClick={() => openView('markets')} type="button">Check market route</button>
                </article>
                <article className="demo-card demo-card--action">
                  <WalletCards size={23} aria-hidden="true" />
                  <p className="demo-overline">Sample margin</p>
                  <h3>{currency.format(projectedMargin)}</h3>
                  <p>Projected after recorded input costs.</p>
                  <button className="text-action text-action--dark" onClick={() => openView('costs')} type="button">Open cost record</button>
                </article>
              </div>
            )}

            {activeView === 'crop' && (
              <div className="scan-layout">
                <div className={`scan-frame scan-frame--${scanState}`} aria-busy={scanState === 'scanning'}>
                  <img
                    alt=""
                    className="scan-photo"
                    decoding="async"
                    height="1600"
                    loading="lazy"
                    src={maizeLeafPhoto}
                    width="1067"
                  />
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
                    <p>Crop checks run on this device. No image is uploaded.</p>
                  )}
                  <div className="demo-actions">
                    <button className="primary-button primary-button--small" disabled={scanState === 'scanning'} onClick={runSampleScan} type="button">
                      {scanState === 'result' ? 'Run again' : scanState === 'scanning' ? 'Checking…' : 'Run sample check'}
                    </button>
                    {scanState === 'result' && (
                      <button className="secondary-button secondary-button--small" disabled={scanSaved} onClick={saveSampleScan} type="button">
                        <Save size={17} aria-hidden="true" /> {scanSaved ? 'Saved locally' : 'Save result'}
                      </button>
                    )}
                  </div>
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
                  <div className="market-list" aria-label="Choose a sample market">
                    {sampleMarkets.map((market) => (
                      <button
                        aria-pressed={selectedMarket.name === market.name}
                        className={selectedMarket.name === market.name ? 'market-row market-row--selected' : 'market-row'}
                        key={market.name}
                        onClick={() => selectMarket(market.name)}
                        type="button"
                      >
                        <span className="market-row-name"><strong>{market.name}</strong><span><Route size={15} aria-hidden="true" /> {market.distance}</span></span>
                        <span>{market.price}</span>
                      </button>
                    ))}
                  </div>
                  <div className="market-selection">
                    <p><strong>{confirmedMarketName ? 'Route saved:' : 'Selected route:'}</strong> {selectedMarket.name}, {selectedMarket.distance}</p>
                    <button className="primary-button primary-button--small" onClick={confirmMarket} type="button">Use this market</button>
                  </div>
                </div>
              </div>
            )}

            {activeView === 'costs' && (
              <div className="cost-layout">
                <div className="cost-summary">
                  <p className="demo-overline">Sample season estimate</p>
                  <strong>{currency.format(projectedMargin)}</strong>
                  <span>projected margin</span>
                </div>
                <div className="cost-lines">
                  <div><span>Expected sales</span><strong>{currency.format(expectedSales)}</strong></div>
                  <div><span>Seed and fertiliser</span><strong>− {currency.format(baseInputCosts + recordedExtraCost)}</strong></div>
                  <div><span>Transport and packaging</span><strong>− {currency.format(transportAndPackaging)}</strong></div>
                  <div className="cost-line-total"><span>What remains</span><strong>{currency.format(projectedMargin)}</strong></div>
                  <div className="demo-actions demo-actions--costs">
                    <button className="primary-button primary-button--small" onClick={addDemoCost} type="button">Add {currency.format(demoCostIncrement)} cost</button>
                    <button className="secondary-button secondary-button--small" disabled={recordedExtraCost === 0} onClick={undoDemoCost} type="button">
                      <Undo2 size={17} aria-hidden="true" /> Undo cost
                    </button>
                  </div>
                </div>
              </div>
            )}
          </div>

          <div className="demo-feedback" role="status" aria-live="polite" aria-atomic="true">
            <span>{statusMessage}</span>
          </div>
        </div>
      </div>
    </section>
  )
}
