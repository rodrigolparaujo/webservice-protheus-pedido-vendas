/*
+----------------------------------------------------------------------------+
!                         FICHA TECNICA DO PROGRAMA                          !
+------------------+---------------------------------------------------------+
!Tipo              ! Webservice                                              !
+------------------+---------------------------------------------------------+
!Modulo            ! FAT - Faturamento                                       !
+------------------+---------------------------------------------------------+
!Nome              ! WSFAT01                                                 !
+------------------+---------------------------------------------------------+
!Descricao         ! Rotina criada para incluir, alterar, excluir e consultar!
!                  ! um pedido de Vendas                                    !
+------------------+---------------------------------------------------------+
!Autor             ! Rodrigo L P Araujo                                      !
+------------------+---------------------------------------------------------+
!Data de Criacao   ! 02/05/2023                                              !
+------------------+---------------------------------------------------------+
*/
#INCLUDE "PROTHEUS.CH"
#INCLUDE "RESTFUL.CH"

#DEFINE PATHLOGSW  GetSrvProfString("Startpath","") + "\ws_log\"

User Function WSFAT01()
	IF !ExistDir(PATHLOGSW)
		MakeDir(PATHLOGSW)
	EndIF
Return

WSRESTFUL PedidoVendas DESCRIPTION 'Pedido de Vendas API' SECURITY 'MATA410' FORMAT "application/json,text/html" 
	WSDATA numero As Character

    WSMETHOD GET ConsultarPedido;
	DESCRIPTION "Consultar Pedido de Vendas" ;
	WSSYNTAX "/PedidoVendas/ConsultarPedido/{numero}";
	PATH "/PedidoVendas/ConsultarPedido";
	PRODUCES APPLICATION_JSON	

    WSMETHOD POST CriarPedido ; 
    DESCRIPTION "Criar Pedido de Vendas" ;
    WSSYNTAX "/PedidoVendas/CriarPedido" ;
    PATH "/PedidoVendas/CriarPedido";
	PRODUCES APPLICATION_JSON

    WSMETHOD PUT AlterarPedido ; 
    DESCRIPTION "Alterar Pedido de Vendas" ;
    WSSYNTAX "/PedidoVendas/AlterarPedido" ;
    PATH "/PedidoVendas/AlterarPedido";
	PRODUCES APPLICATION_JSON

    WSMETHOD DELETE ExcluirPedido ; 
    DESCRIPTION "Excluir Pedido de Vendas" ;
    WSSYNTAX "/PedidoVendas/ExcluirPedido/{numero}" ;
    PATH "/PedidoVendas/ExcluirPedido";
	PRODUCES APPLICATION_JSON

ENDWSRESTFUL

/*
método GET - Consulta Pedido de Vendas
exemplo: http://localhost:3000/rest/PedidoVendas/ConsultarPedido?numero=000001
*/
WSMETHOD GET ConsultarPedido QUERYPARAM numero WSREST PedidoVendas
	Local lRet      := .T.
	Local aData     := {}
	Local oData     := NIL
	Local oAlias   := GetNextAlias()
	Local cPedido   := Self:numero

    /*
    Parametros de pesquisa
    */
	if Empty(cPedido)
		Self:SetResponse('{"noPedido":"' + cPedido + '", "infoMessage":"", "errorCode":"404", "errorMessage":"Numero do Pedido nao informado"}')
		Return(.F.)
	EndIF

	BeginSQL Alias oAlias
        SELECT 
         C5_NUM     
        ,C5_EMISSAO
        ,C5_CLIENTE
        ,C5_LOJACLI
        ,C5_TIPO
        ,C5_CONDPAG
        ,C5_MOEDA
        ,C6_ITEM
        ,C6_PRODUTO
        ,C6_UM     
        ,C6_QTDVEN 
        ,C6_VALOR  
        ,C6_LOCAL  
        ,C6_TES    
        FROM %Table:SC6% SC6
        INNER JOIN %Table:SC5% SC5 ON SC5.%NotDel% AND SC5.C5_FILIAL = %xFilial:SC5% AND C5_NUM = C6_NUM
        WHERE SC6.C6_FILIAL = %xFilial:SC6%
            AND SC6.%NotDel%
            AND C6_NUM = %exp:cPedido%
		ORDER BY C5_NUM
	EndSQL

	dbSelectArea(oAlias)
	(oAlias)->(dbGoTop())
	IF (oAlias)->(!Eof())
		oData := JsonObject():New()

		//Monta o cabeçalho
		oData[ 'noPedido' ]     := Alltrim((oAlias)->C5_NUM)
		oData[ 'dataEmissao' ]  := Alltrim((oAlias)->C5_EMISSAO)
		oData[ 'noCliente' ]    := Alltrim((oAlias)->C5_CLIENTE + (oAlias)->C5_LOJACLI)
		oData[ 'tipo' ]         := Alltrim((oAlias)->C5_TIPO)
		oData[ 'condicaoPago' ] := Alltrim((oAlias)->C5_CONDPAG)
		oData[ 'moeda' ]        := Alltrim((oAlias)->C5_MOEDA)

		aAdd(aData,oData)

		oData["items"]   := Array(0)

		While (oAlias)->(!Eof())

			aadd(oData["items"], JsonObject():New())
			aTail(oData[ 'items' ])[ 'item' ]          := Alltrim((oAlias)->C6_ITEM )
			aTail(oData[ 'items' ])[ 'produto' ]       := Alltrim((oAlias)->C6_PRODUTO)
			aTail(oData[ 'items' ])[ 'uom' ]           := Alltrim((oAlias)->C6_UM )
			aTail(oData[ 'items' ])[ 'quantidade' ]    := (oAlias)->C6_QTDVEN
			aTail(oData[ 'items' ])[ 'precoUnitario' ] := (oAlias)->C6_VALOR
			aTail(oData[ 'items' ])[ 'total' ]         := (oAlias)->C6_QTDVEN * (oAlias)->C6_VALOR
			aTail(oData[ 'items' ])[ 'aramzem' ]       := Alltrim((oAlias)->C6_LOCAL )
			aTail(oData[ 'items' ])[ 'tes' ]           := Alltrim((oAlias)->C6_TES )

			(oAlias)->(dbSkip())
		EndDo

		FreeObj(oData)

		//Define o retorno do método
		Self:SetResponse(FwJsonSerialize(aData))

	ELSE
		Self:SetResponse('{"noPedido":"'+cPedido+'", "infoMessage":"", "errorCode":"404", "errorMessage":"Numero do Pedido não encontrado"}') 
		lRet    := .F.
	EndIF

	(oAlias)->(dbCloseArea())

Return(lRet)

/*
método POST - Criar Pedido de Vendas
exemplo: http://localhost:3000/rest/PedidoVendas/CriarPedido
*/
WSMETHOD POST CriarPedido WSSERVICE PedidoVendas
	Local lRet      := .T.
	Local oJson     := Nil
    Local oItems    := Nil
	Local cJson     := Self:GetContent()
	Local cError    := ""
    Local cPedido   := ""
    Local cCliLoja  := ""
    Local cCliente  := ""
    Local cLoja     := ""
    Local nMoeda    := 1
    Local cCondPag  := ""
    Local cTES      := ""
	Local nQtde     := 0
	Local nValor    := 0
	Local nTotal    := 0
    Local aCabec    := {}
    Local aItens    := {}
    Local aItem     := {}
    Local i         := 0

	Private lMsErroAuto    := .F.
	Private lMsHelpAuto    := .T.
	Private lAutoErrNoFile := .T.

	//Se não existir o diretório de logs dentro da Protheus Data, será criado
	IF !ExistDir(PATHLOGSW)
		MakeDir(PATHLOGSW)
	EndIF

    FwLogMsg("INFO",, "CriarPedido", "WSFAT01", "", "01", "Iniciando")

	//Definindo o conteúdo como JSON, e pegando o content e dando um parse para ver se a estrutura está ok
	Self:SetContentType("application/json")
	oJson   := JsonObject():New()
	cError  := oJson:FromJson(cJson)

	//Se tiver algum erro no Parse, encerra a execução
	IF !Empty(cError)
		FwLogMsg("ERROR",, "CriarPedido", "WSFAT01", "", "01", 'Parser Json Error')
        Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"500" ,  "errorMessage":"Parser Json Error" }')
		lRet    := .F.
	Else
        //Lendo o cabeçalho do arquivo JSON
        cCliLoja := Alltrim(oJson:GetJsonObject('noCliente'))
		cCliente := Left(cCliLoja,6)
		cLoja    := Right(cCliLoja,2)
		nMoeda   := IIF(Empty(oJson:GetJsonObject('moeda')),1,oJson:GetJsonObject('moeda'))
		cCondPag := PadR(oJson:GetJsonObject('condicaoPago'),TamSX3("C5_CONDPAG")[1])

        //Verifica se o cliente existe			    
        If !(Existe("SA1",1,cCliLoja))
            FwLogMsg("ERROR",, "CriarPedido", "WSFAT01", "", "01", "Cliente: "+ Alltrim(cCliLoja) +" nao existe!")
            Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"404" ,  "errorMessage":"O Cliente '+ cCliente + " - loja " + cLoja +' nao existe" }')
            FreeObj(oJson)
            Return(.F.)
        Endif

        //Verifica se a condição de pagamento existe			    
        If !(Existe("SE4",1,cCondPag))
            FwLogMsg("ERROR",, "CriarPedido", "WSFAT01", "", "01", "Condicao de Pagamento: "+ Alltrim(cCondPag) +" nao existe!")
            Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"404" ,  "errorMessage":"Condicao de Pagamento '+ Alltrim(cCondPag) +' nao existe" }')
            FreeObj(oJson)
            Return(.F.)
        Endif

        //Lendo os itens do arquivo JSON
        oItems  := oJson:GetJsonObject('items')
        IF ValType( oItems ) == "A"

            //Monta o cabeçalho do pedido de Vendas apenas se houver itens
            cPedido := GetSxeNum("SC5","C5_NUM")

            aAdd(aCabec,{"C5_FILIAL" , xFilial("SC5")	, NIL})
            aAdd(aCabec,{"C5_NUM"    , cPedido			, NIL})
            aAdd(aCabec,{"C5_EMISSAO", dDataBase		, NIL})
            aAdd(aCabec,{"C5_CLIENTE", cCliente			, NIL})
            aAdd(aCabec,{"C5_LOJACLI", cLoja			, NIL})
            aAdd(aCabec,{"C5_CONDPAG", cCondPag			, NIL})
            aAdd(aCabec,{"C5_MOEDA"  , nMoeda	 		, NIL})
            aAdd(aCabec,{"C5_TIPO"   , "N"  	 		, NIL})

            For i  := 1 To Len (oItems)
                cProduto := PadR(AllTrim(oItems[i]:GetJsonObject( 'produto' )),TamSX3("C6_PRODUTO")[1])
                nQtde    := oItems[i]:GetJsonObject( 'quantidade' )
                cTES     := oItems[i]:GetJsonObject( 'tes' )
                nValor   := oItems[i]:GetJsonObject( 'precoUnitario' )
                nTotal   := nQtde * nValor

                //Verifica se o produto existe			    
                If !(Existe("SB1",1,cProduto))
                    FwLogMsg("ERROR",, "CriarPedido", "WSFAT01", "", "01", "Produto: "+ Alltrim(cProduto) +" nao existe!")
                    Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"404" ,  "errorMessage":"O produto '+ Alltrim(cProduto) +' nao existe" }')
                    FreeObj(oJson)
                    Return(.F.)
                Endif

                aItem:= {}
                aAdd(aItem,{"C6_ITEM"	,  StrZero(i,2)	, NIL})
                aAdd(aItem,{"C6_PRODUTO",  cProduto		, NIL})
                aAdd(aItem,{"C6_QTDVEN"	,  nQtde		, NIL})
                aAdd(aItem,{"C6_PRCVEN"	,  nValor		, NIL})
                aAdd(aItem,{"C6_VALOR"	,  nTotal		, NIL})
                aAdd(aItem,{"C6_TES"	,  cTES		    , NIL})
                aAdd(aItens,aItem)

            Next

            //Executa a inclusão automática de pedido de Vendas
            FwLogMsg("INFO",, "CriarPedido", "WSFAT01", "", "01", "MSExecAuto")
		    MsExecAuto({|x, y, z| Mata410(x, y, z)}, aCabec, aItens, 3)

            //Se houve erro, gera um arquivo de log dentro do diretório da protheus data
            IF lMsErroAuto
                RollBackSX8()
                cArqLog  := "CriarPedido-" + cCliLoja + "-" + DTOS(dDataBase) + "-" + StrTran(Time(), ':' , '-' )+".log"
                aLogAuto := {}
                aLogAuto := GetAutoGrLog()
                cError   := GravaLog(cArqLog,aLogAuto)

                FwLogMsg("ERROR",, "CriarPedido", "WSFAT01", "", "01", cError )
                Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"500" ,  "errorMessage":"'+ Alltrim(cError) +'" }')
                lRet    := .F.
            ELSE
                ConfirmSX8()
                FwLogMsg("INFO",, "CriarPedido", "WSFAT01", "", "01", "Pedido criado: " + cPedido)
                Self:SetResponse('{"noPedido":"'+cPedido+'", "infoMessage":"PEDIDO CRIADO COM SUCESSO", "errorCode":"", "errorMessage":"" }')
            EndIF

        Else
            FwLogMsg("ERROR",, "CriarPedido", "WSFAT01", "", "01", "Item nao informado")
            Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"500" ,  "errorMessage":"Item nao informado" }')
            FreeObj(oJson)
            lRet    := .F.
        Endif        
    Endif

	FreeObj(oJson)
Return(lRet)

/*
método PUT - Alterar Pedido de Vendas
exemplo: http://localhost:3000/rest/PedidoVendas/AlterarPedido
*/
WSMETHOD PUT AlterarPedido WSSERVICE PedidoVendas
	Local lRet      := .T.
	Local oJson     := Nil
    Local oItems    := Nil
	Local cJson     := Self:GetContent()
	Local cError    := ""
    Local cPedido   := ""
    Local cCliLoja := ""
    Local cFornece  := ""
    Local cLoja     := ""
    Local cItem     := ""
	Local nQtde     := 0
	Local nValor    := 0
	Local nTotal    := 0
    Local aCabec    := {}
    Local aItens    := {}
    Local aItem     := {}
    Local i         := 0

	Private lMsErroAuto    := .F.
	Private lMsHelpAuto    := .T.
	Private lAutoErrNoFile := .T.

	//Se não existir o diretório de logs dentro da Protheus Data, será criado
	IF !ExistDir(PATHLOGSW)
		MakeDir(PATHLOGSW)
	EndIF

    FwLogMsg("INFO",, "AlterarPedido", "WSFAT01", "", "01", "Iniciando")

	//Definindo o conteúdo como JSON, e pegando o content e dando um parse para ver se a estrutura está ok
	Self:SetContentType("application/json")
	oJson   := JsonObject():New()
	cError  := oJson:FromJson(cJson)

	//Se tiver algum erro no Parse, encerra a execução
	IF !Empty(cError)
		FwLogMsg("ERROR",, "AlterarPedido", "WSFAT01", "", "01", 'Parser Json Error')
        Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"500" ,  "errorMessage":"Parser Json Error" }')
		lRet    := .F.
	Else
        //Lendo o cabeçalho do arquivo JSON
        cPedido  := Alltrim(oJson:GetJsonObject('noPedido'))
        cCliLoja:= Alltrim(oJson:GetJsonObject('noCliente'))
		cFornece := Left(cCliLoja,6)
		cLoja    := Right(cCliLoja,2)

        //Verifica se o fornecedor existe			    
        If !(Existe("SA2",1,cCliLoja))
            FwLogMsg("ERROR",, "AlterarPedido", "WSFAT01", "", "01", "Cliente: "+ Alltrim(cCliLoja) +" nao existe!")
            Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"404" ,  "errorMessage":"O fornecedor '+ cFornece + " - loja " + cLoja +' nao existe" }')
            FreeObj(oJson)
            Return(.F.)
        Endif

        //Verifica se o pedido de Vendas existe			    
        dbSelectArea("SC5")
        SC5->(dbSetOrder(1))
        SC5->(dbGoTop())
        If SC5->(dbSeek(xFilial("SC5") + cPedido))
            //Monta o cabeçalho do pedido de Vendas apenas se houver itens
            aadd(aCabec,{"C5_NUM"       , cPedido})
            aadd(aCabec,{"C5_EMISSAO"   , SC5->C5_EMISSAO})
            aadd(aCabec,{"C5_FORNECE"   , cFornece})
            aadd(aCabec,{"C5_LOJACLI"      , cLoja})
            aadd(aCabec,{"C5_COND"      , SC5->C5_COND})
            aadd(aCabec,{"C5_CONTATO"   , SC5->C5_CONTATO})
            aadd(aCabec,{"C5_FILENT"    , SC5->C5_FILENT})

            //Lendo os itens do arquivo JSON
            oItems  := oJson:GetJsonObject('items')
            IF ValType( oItems ) == "A"
                For i  := 1 To Len (oItems)
                    cItem    := oItems[i]:GetJsonObject( 'item' )
                    cProduto := PadR(AllTrim(oItems[i]:GetJsonObject( 'produto' )),TamSX3("C5_PRODUTO")[1])
                    nQtde    := oItems[i]:GetJsonObject( 'quantidade' )
                    nValor   := oItems[i]:GetJsonObject( 'precoUnitario' )
                    nTotal   := nQtde * nValor

                    //Verifica se o produto existe			    
                    If !(Existe("SB1",1,cProduto))
                        FwLogMsg("ERROR",, "AlterarPedido", "WSFAT01", "", "01", "Produto: "+ Alltrim(cProduto) +" nao existe!")
                        Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"404" ,  "errorMessage":"O produto '+ Alltrim(cProduto) +' nao existe" }')
                        FreeObj(oJson)
                        Return(.F.)
                    Endif

                    aItem:= {}
                    aAdd(aItem,{"C5_ITEM"	, PADL(cItem,4,"0") , NIL})
                    aAdd(aItem,{"C5_PRODUTO", cProduto		    , NIL})
                    aAdd(aItem,{"C5_QUANT"	, nQtde		        , NIL})
                    aAdd(aItem,{"C5_PRECO"	, nValor		    , NIL})
                    aAdd(aItem,{"C5_TOTAL"	, nTotal		    , NIL})
                    aAdd(aItem,{"LINPOS"    , "C5_ITEM" ,PADL(cItem,4,"0")})
                    aadd(aItem,{"AUTDELETA"	, "N"			    , Nil})	
                    aAdd(aItens,aItem)

                Next

                //Executa a inclusão automática de pedido de Vendas
                FwLogMsg("INFO",, "AlterarPedido", "WSFAT01", "", "01", "MSExecAuto")
                MSExecAuto({|a,b,c,d,e| MATA120(a,b,c,d,e)},1,aCabec,aItens,4,.F.)

                //Se houve erro, gera um arquivo de log dentro do diretório da protheus data
                IF lMsErroAuto
                    cArqLog  := "AlterarPedido-" + cCliLoja + "-" + DTOS(dDataBase) + "-" + StrTran(Time(), ':' , '-' )+".log"
                    aLogAuto := {}
                    aLogAuto := GetAutoGrLog()
                    cError   := GravaLog(cArqLog,aLogAuto)

                    FwLogMsg("ERROR",, "AlterarPedido", "WSFAT01", "", "01", cError )
                    Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"500" ,  "errorMessage":"'+ Alltrim(cError) +'" }')
                    lRet    := .F.
                ELSE
                    FwLogMsg("INFO",, "AlterarPedido", "WSFAT01", "", "01", "Pedido alterado: " + cPedido)
                    Self:SetResponse('{"noPedido":"'+cPedido+'", "infoMessage":"PEDIDO ALTERADO COM SUCESSO", "errorCode":"", "errorMessage":"" }')
                EndIF

            Else
                FwLogMsg("ERROR",, "AlterarPedido", "WSFAT01", "", "01", "Item nao informado")
                Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"500" ,  "errorMessage":"Item nao informado" }')
                FreeObj(oJson)
                lRet    := .F.
            Endif 
        Else
            FwLogMsg("ERROR",, "AlterarPedido", "WSFAT01", "", "01", "Pedido: "+ Alltrim(cPedido) +" nao existe!")
            Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"404" ,  "errorMessage":"O pedido de Vendas '+ cPedido +' nao existe" }')
            FreeObj(oJson)
            lRet := .F.
        Endif               
    Endif

	FreeObj(oJson)
Return(lRet)

/*
método DELETE - Excluir Pedido de Vendas
exemplo: http://localhost:3000/rest/PedidoVendas/ExcluirPedido
*/
WSMETHOD DELETE ExcluirPedido WSSERVICE PedidoVendas
	Local lRet      := .T.
	Local oJson     := Nil
	Local cJson     := Self:GetContent()
	Local cError    := ""
    Local cPedido   := ""
    Local cCliLoja := ""
    Local cFornece  := ""
    Local cLoja     := ""
    Local aCabec    := {}
    Local aItens    := {}

	Private lMsErroAuto    := .F.
	Private lMsHelpAuto    := .T.
	Private lAutoErrNoFile := .T.

	//Se não existir o diretório de logs dentro da Protheus Data, será criado
	IF !ExistDir(PATHLOGSW)
		MakeDir(PATHLOGSW)
	EndIF

    FwLogMsg("INFO",, "ExcluirPedido", "WSFAT01", "", "01", "Iniciando")

	//Definindo o conteúdo como JSON, e pegando o content e dando um parse para ver se a estrutura está ok
	Self:SetContentType("application/json")
	oJson   := JsonObject():New()
	cError  := oJson:FromJson(cJson)

	//Se tiver algum erro no Parse, encerra a execução
	IF !Empty(cError)
		FwLogMsg("ERROR",, "ExcluirPedido", "WSFAT01", "", "01", 'Parser Json Error')
        Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"500" ,  "errorMessage":"Parser Json Error" }')
		lRet    := .F.
	Else
        //Lendo o cabeçalho do arquivo JSON
        cPedido  := Alltrim(oJson:GetJsonObject('noPedido'))
        cCliLoja:= Alltrim(oJson:GetJsonObject('noCliente'))
		cFornece := Left(cCliLoja,6)
		cLoja    := Right(cCliLoja,2)

        //Verifica se o fornecedor existe			    
        If !(Existe("SA2",1,cCliLoja))
            FwLogMsg("ERROR",, "ExcluirPedido", "WSFAT01", "", "01", "Cliente: "+ Alltrim(cCliLoja) +" nao existe!")
            Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"404" ,  "errorMessage":"O fornecedor '+ cFornece + " - loja " + cLoja +' nao existe" }')
            FreeObj(oJson)
            Return(.F.)
        Endif

        //Verifica se o pedido de Vendas existe			    
        dbSelectArea("SC5")
        SC5->(dbSetOrder(1))
        SC5->(dbGoTop())
        If SC5->(dbSeek(xFilial("SC5") + cPedido))
            //Monta o cabeçalho do pedido de Vendas apenas se houver itens
            aadd(aCabec,{"C5_NUM"       , cPedido})
            aadd(aCabec,{"C5_FORNECE"   , cFornece})
            aadd(aCabec,{"C5_LOJA"      , cLoja})

            //Executa a inclusão automática de pedido de Vendas
            FwLogMsg("INFO",, "ExcluirPedido", "WSFAT01", "", "01", "MSExecAuto")
            MSExecAuto({|a,b,c,d,e| MATA120(a,b,c,d,e)},1,aCabec,aItens,5,.F.)

            //Se houve erro, gera um arquivo de log dentro do diretório da protheus data
            IF lMsErroAuto
                cArqLog  := "ExcluirPedido-" + cCliLoja + "-" + DTOS(dDataBase) + "-" + StrTran(Time(), ':' , '-' )+".log"
                aLogAuto := {}
                aLogAuto := GetAutoGrLog()                
                cError   := GravaLog(cArqLog,aLogAuto)

                FwLogMsg("ERROR",, "ExcluirPedido", "WSFAT01", "", "01", cError )
                Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"500" ,  "errorMessage":"'+ Alltrim(cError) +'" }')
                lRet    := .F.
            ELSE
                FwLogMsg("INFO",, "ExcluirPedido", "WSFAT01", "", "01", "Pedido Excluido: " + cPedido)
                Self:SetResponse('{"noPedido":"'+cPedido+'", "infoMessage":"PEDIDO EXCLUIDO COM SUCESSO", "errorCode":"", "errorMessage":"" }')
            EndIF
        Else
            FwLogMsg("ERROR",, "ExcluirPedido", "WSFAT01", "", "01", "Pedido: "+ Alltrim(cPedido) +" nao existe!")
            Self:SetResponse('{"noPedido":"", "infoMessage":"", "errorCode":"404",  "errorMessage":"O pedido de Vendas '+ cPedido +' nao existe" }')
            FreeObj(oJson)
            lRet := .F.
        Endif               
    Endif

	FreeObj(oJson)
Return(lRet)

//Função para consulta simples se um registro existe
//Sintaxe: Existe("SB1",1,"090100243")
//Retorno: .F. ou .T.
Static Function Existe(cTabela,nOrdem,cConteudo)
	Local lRet   := .F.

	dbSelectArea(cTabela)
	(cTabela)->(dbSetOrder(nOrdem))
	(cTabela)->(dbGoTop())
	If (cTabela)->(dbSeek(xFilial(cTabela) + cConteudo))
		lRet := .T.
	Endif
Return(lRet)

Static Function GravaLog(cArqLog,aLogAuto)
    Local i     := 0
    Local cErro := ""

    For i := 1 To Len(aLogAuto)
        cErro += EncodeUTF8(aLogAuto[i])+CRLF
    Next i

    MemoWrite(PATHLOGSW + "\" + cArqLog,cErro)
Return(cErro)
