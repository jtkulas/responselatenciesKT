library(surveydown)
library(shinyjs)

db <- sd_db_connect()

# ==================== UI ====================
ui <- fluidPage(
  useShinyjs(),
  sd_ui()
)

# ==================== SERVER ====================
server <- function(input, output, session) {
  
  # MILLISECOND LATENCY TRACKING
  shinyjs::runjs('
    let pageStartTime = 0;
    let currentPageId = "";

    function initLatency() {
      const observer = new MutationObserver(() => {
        $(".sd-page:visible").each(function() {
          const id = $(this).attr("id");
          if (id && id !== currentPageId) {
            currentPageId = id;
            pageStartTime = performance.now();
          }
        });
      });
      observer.observe(document.body, { childList: true, subtree: true, attributes: true });

      $(document).on("click", "button.sd-next-btn, button:contains(\'Next\')", function() {
        if (pageStartTime > 0) {
          const latencyMs = Math.round(performance.now() - pageStartTime);
          Shiny.setInputValue("response_latency_ms", 
            { page_id: currentPageId, latency_ms: latencyMs }, 
            {priority: "event"});
        }
      });
    }

    $(document).on("shiny:connected", () => setTimeout(initLatency, 1000));
    setTimeout(initLatency, 2200);
  ')
  
  # SAVE LATENCY TO SUPABASE
  observeEvent(input$response_latency_ms, {
    req(input$response_latency_ms)
    lat <- input$response_latency_ms
    
    tryCatch({
      pool::poolWithTransaction(db$db, function(con) {
        DBI::dbExecute(con,
                       "INSERT INTO latency_events (session_token, page_id, latency_ms, recorded_at)
           VALUES ($1, $2, $3, NOW())",
                       params = list(session$token, lat$page_id, lat$latency_ms)
        )
      })
    }, error = function(e) {
      # Silent fail in production
    })
  })
  
  # MUST BE THE LAST LINE
  sd_server(db = db)
}

shinyApp(ui, server)