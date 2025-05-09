#' A shiny app to facilitate the creation of a manual labelling of matches
#' @param dir the directory to have the file selector start in
#' @param p data.frame of pairs
#' @param data1 data.frame of identifiers for pairs
#' @param data2 data.frame of identifiers for pairs
#' @param data_id1 column in data1 representing row id. Should be related to the `id1` column in p(airs)
#' @param data_id2 column in data1 representing row id. Should be related to the `id2` column in p(airs)
#' @param ... passed to shiny::shinyApp
#' @export
#' @import shiny shinyFiles data.table
#' @importFrom fs path_home
#' @importFrom tools file_ext
#' @importFrom DT DTOutput renderDT formatStyle datatable styleEqual
#' @importFrom utils write.csv
matchmaker = function(dir = NULL, p = NULL, data1 = NULL, data2 = NULL, data_id1 = NULL, data_id2 = NULL, ...){

  if(!is.null(p)){
    p = as.data.table(p)
    if(!'pair' %in% names(p)) p[, pair := NA_integer_]
  }
  if(!is.null(data1)) data1 = as.data.table(data1)
  if(!is.null(data2)) data2 = as.data.table(data2)

  ui <- fluidPage(

    # Application title
    titlePanel("Find The Match!"),

    # Sidebar
    sidebarLayout(
      sidebarPanel(
        tags$h4('Load Data:'),
        # Since this will be run locally, we just need the file path, not a copy of the file
        shinyFiles::shinyFilesButton('loadPairs', 'Select Pairs File', 'Please select a file', FALSE),
        tags$br(),
        shinyFiles::shinyFilesButton('loadData1', 'Select Data1 File', 'Please select a file', FALSE),
        tags$br(),
        shinyFiles::shinyFilesButton('loadData2', 'Select Data2 File', 'Please select a file', FALSE),
        tags$br(),
        conditionalPanel('output.filesLoaded == 1',
                         tags$h4('Navigation:'),

                         #Navigate to pairs
                         uiOutput('selection'),

                         tags$h4('Select cols:'),

                         # drop down for ID 1
                         uiOutput('id1'),

                         # drop down for ID 2
                         uiOutput('id2'),

                         # Check box for variables to compare
                         uiOutput('comparevars'),

                         tags$h4('Save Results:'),
                         # Save Results
                         downloadButton("downloadMatches", "Save Results")
        )


      ),

      # Show a plot of the generated distribution
      mainPanel(
        tabsetPanel(
          tabPanel('Make Matches',
                   br(),
                   conditionalPanel('output.filesLoaded == 0', tags$h4('To get started, you will need to load a pairs file as well as two data files')),
                   #uiOutput('mismatchcols'),
                   uiOutput('status'),
                   hr(),
                   DTOutput('compare'),
                   hr(),
                   conditionalPanel("output.showButtons == 1",
                                    fluidRow(
                                      actionButton('previous', 'Previous'),
                                      actionButton('nomatch', 'No Match!'),
                                      actionButton('flag', 'Flag'),
                                      actionButton('match', 'Match!'),
                                      actionButton('nextone', 'Next')
                                    ),
                                    br(),
                                    tableOutput('sum'),
                                    br(),
                                    tags$h4('Match breakdown'),
                                    htmlOutput('filestatus')
                   )
          ),
          tabPanel('Review Results',
                   DT::DTOutput('pair_view'))
        )
      )
    )
  )
  server <- function(input, output) {

    readFile = function(x){
      if(tools::file_ext(x) == 'rds'){
        r = readRDS(x)
        stopifnot(inherits(r, 'data.frame'))
        return(data.table::as.data.table(r))
      }else if(tools::file_ext(x) == 'parquet'){
        r = arrow::read_parquet(x)
        setDT(x)
      }else{
        return(fread(x))
      }
    }

    # General file handling
    volumes  = c(main = dir,
                 wd = getwd(),
                 Home = fs::path_home(),
                 getVolumes()())
    # Pair handling ----
    shinyFiles::shinyFileChoose(input, 'loadPairs', roots = volumes, filetypes = c('csv', 'rds', 'parquet'))
    pairs = reactiveVal(p)
    pairf = reactiveVal(':memory:')
    observeEvent(input$loadPairs,{
      req(is.list(input$loadPairs))
      fp = parseFilePaths(volumes, input$loadPairs)
      fp = fp$datapath[1]
      r = readFile(fp)
      if(!'pair' %in% names(r)) r[, pair := NA_integer_]
      if(!c('id1', 'id2') %in% names(r)) return(tags$strong('pairs dataset must have `id1` and `id2` columns'))
      pairs(r)
      pairf(fp)
    })

    # Pair viewing ----
    output$pair_view = DT::renderDT({
      req(pairs())
      pairs()
    })

    # Data handling ----
    d1 = reactiveVal(data1)
    d2 = reactiveVal(data2)
    d1f = reactiveVal(':memory:')
    d2f = reactiveVal(':memory:')
    shinyFiles::shinyFileChoose(input, 'loadData1', roots = volumes, filetypes = c('csv', 'rds', 'parquet'))
    observeEvent(input$loadData1,{
      req(is.list(input$loadData1))
      fp = parseFilePaths(volumes, input$loadData1)
      fp = fp$datapath[1]
      r = readFile(fp)
      d1(r)
      d1f(fp)
    })

    shinyFiles::shinyFileChoose(input, 'loadData2', roots = volumes, filetypes = c('csv', 'rds', 'parquet'))
    observeEvent(input$loadData2,{
      req(is.list(input$loadData2))
      fp = parseFilePaths(volumes, input$loadData2)
      fp = fp$datapath[1]
      r = readFile(fp)
      d2(r)
      d2f(fp)
    })

    # ID selection ----
    output$id1 = renderUI({
      req(d1())
      selectInput('id1', 'ID variable for Data1', choices = names(d1()),selected = data_id1)
    })

    output$id2 = renderUI({
      req(d2())
      selectInput('id2', 'ID variable for Data2', choices = names(d2()), selected = data_id2)
    })

    # Selecting comparison variables ----
    output$comparevars = renderUI({
      req(d1(), d2())
      pos = intersect(names(d1()), names(d2()))
      checkboxGroupInput('comparevars', 'Comparison Variables', choices = pos, selected = pos)

    })

    # file status ----
    output$filestatus = renderUI({
      filelist = list(pairs = pairf(),
                      data1 = d1f(),
                      data2 = d2f())
      fs = lapply(seq_along(filelist), function(i){
        paste0(names(filelist)[i],': ', filelist[[i]])
      })

      HTML(as.character(tagList(
        h4('Files Loaded'),
        h5(fs[[1]]),
        h5(fs[[2]]),
        h5(fs[[3]])
      )))



    })

    # warning about mismatched columns ----
    idcheck = reactiveVal(T)
    # output$mismatchcols = renderUI({
    #   req(input$id1, input$id2, pairs())
    #   if(!all(c(input$id1, input$id2) %in% names(pairs()))){
    #     idcheck(NULL)
    #     return(
    #       tags$strong('ID columns must also exist in `pairs` file')
    #     )
    #   }else{
    #     idcheck(T)
    #     return(NULL)
    #   }
    #
    # })

    # index ----
    index = reactiveVal(1)
    output$selection = renderUI({
      req(pairs())
      numericInput('selection',label = 'Index', value = 1, min = 1, max = nrow(pairs()))
    })
    observeEvent(input$selection, index(input$selection))

    # # Comparison data
    output$compare <- renderDT({
      req(index(), d1(), d2(),input$comparevars, pairs(), idcheck())



      p = pairs()[index()]
      s1 = d1()[get(input$id1) == p[['id1']], .SD, .SDcols = unique(c(input$id1, input$comparevars))]
      s2 = d2()[get(input$id2) == p[['id2']], .SD, .SDcols = unique(c(input$id2, input$comparevars))]

      if(nrow(s1) == 0 || nrow(s2) == 0) return(data.table('0 rows found in data1 or data2 for this pair. Maybe the id column input is wrong?'))

      s1 = s1[, lapply(.SD, as.character)]
      s1 = melt(s1, id.vars = input$id1, value.name = 'Person1')
      s1 = s1[, .(variable, Person1)]
      s2 = s2[, lapply(.SD, as.character)]
      s2 = melt(s2, id.vars = input$id2, value.name = 'Person2')
      s2 = s2[, .(variable, Person2)]

      r = merge(s1, s2, all = T, by = 'variable')

      r[, order_cols := match(variable, input$comparevars)]

      setorder(r, order_cols)

      r[, c('order_cols') := NULL]
      r = rbind(r, data.table(variable = 'id', Person1 = p$id1, Person2 = p$id2))
      r[, equal := as.character(Person1 == Person2)]
      r[is.na(equal), equal := 'MAYBE']

      DT::datatable(r, options = list(pageLength = 25)) %>%
        DT::formatStyle('equal', target = 'row',
                        backgroundColor = DT::styleEqual(c('FALSE', "TRUE", 'MAYBE'), c('#beaed4','#7fc97f','#fdc086')))



    })


    # A toggle to display buttons ----
    displayButtons = reactiveVal(0)
    observe({
      displayButtons(0)
      req(index(), d1(), d2(),input$comparevars, pairs(), idcheck())
      displayButtons(1)
    })
    output$showButtons <- reactive(displayButtons())
    outputOptions(output, 'showButtons', suspendWhenHidden = FALSE)

    # A toggle to display selection options
    filesLoaded = reactiveVal(0)
    observe({
      filesLoaded(0)
      req(d1(), d2(), pairs())
      filesLoaded(1)
    })
    output$filesLoaded <- reactive(filesLoaded())
    outputOptions(output, 'filesLoaded', suspendWhenHidden = FALSE)

    # Navigation buttons ----
    ## Previous ----
    observeEvent(input$previous, {
      req(input$selection)
      updateNumericInput(inputId = 'selection', value = max(c(1, input$selection -1)))
    })

    # Next one, given next, match, no match, or flag
    npairs = reactive({
      req(pairs())
      nrow(pairs())
    })
    observeEvent(input$nextone, {
      req(input$selection)
      updateNumericInput(inputId = 'selection', value = min(c(npairs(), input$selection + 1)))
    })
    observeEvent(input$match, {
      req(input$selection)
      updateNumericInput(inputId = 'selection', value = min(c(npairs(), input$selection + 1)))
    })
    observeEvent(input$nomatch, {
      req(input$selection)
      updateNumericInput(inputId = 'selection', value = min(c(npairs(), input$selection + 1)))
    })
    observeEvent(input$flag, {
      req(input$selection)
      updateNumericInput(inputId = 'selection', value = min(c(npairs(), input$selection + 1)))
    })

    # Change pairs value with button press ----
    ## match
    observeEvent(input$match, {
      req(pairs())
      r = pairs()
      r[index(), pair := 1L]
      pairs(r)

    })
    ## Not a match
    observeEvent(input$nomatch, {
      req(pairs())
      r = pairs()
      r[index(), pair := 0L]
      pairs(r)
    })

    ## flag
    observeEvent(input$flag, {
      req(pairs())
      r = pairs()
      r[index(), pair := -1L]
      pairs(r)

    })

    # Running results ----
    output$sum = renderTable({
      req(pairs())
      c(input$nomatch, input$match, input$flag)
      r = pairs()[, .N, pair]
      r
    })

    # Status
    output$status = renderUI({
      req(displayButtons()==1)

      stat = paste('Status: ', pairs()[index(), pair])
      tags$strong(stat)
    })


    # Download file ----
    output$downloadMatches <- downloadHandler(
      filename = 'pairs.csv',
      content = function(file){
        write.csv(pairs(), file, row.names = FALSE)
      },
      contentType = 'text/csv'
    )
  }

  # Run the application
  shiny::shinyApp(ui = ui, server = server, ...)
}
