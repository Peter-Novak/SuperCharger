/*
****************************************************************************************************************************************************************************************
*                                                                                                                                                                                      *
* SuperChargerUltra-01.mq4     
* Postopno večanje števila pozicij, multithreaded                                                                                                                                                   *
*                                                                                                                                                                                      *
* Copyright Peter Novak ml., M.Sc.                                                                                                                                                     *
****************************************************************************************************************************************************************************************
*/

#property copyright "Peter Novak ml., M.Sc."
#property link      "http://www.marlin.si"



// Vhodni parametri --------------------------------------------------------------------------------------------------------------------------------------------------------------------
extern double d;                     // Razdalja med ravnemi.
extern double L;                     // Velikost posamezne pozicije v lotih.
extern double p;                     // Profitni cilj.
extern int    stevilkaIteracije;     // Enolična oznaka iteracije.
extern int    samodejniPonovniZagon; // Samodejni ponovni zagon - DA(>0) ali NE(0). 



// Globalne konstante ------------------------------------------------------------------------------------------------------------------------------------------------------------------
#define MAX_POZ     99  // Največje možno število ravni odprtih v eno smer.
#define MAX_NITI    20  // Največje možno število hkratnih niti algoritma.
#define NAPAKA     -5   // Oznaka za povratno vrednost pri neuspešno izvedenem klicu funkcije.
#define USPEH      -4   // Oznaka za povratno vrednost pri uspešno izvedenem klicu funkcije.
#define ZAPRTA     -3   // Oznaka v poljih bpozicije / spozicije - označuje da je bila pozicija zaprta (ne vemo pa ID-ja pozicije).
#define SS          9   // Oznaka za stanje SS - NovaNit
#define S0          1   // Oznaka za stanje S0 - Čakanje na zagon.
#define S1          2   // Oznaka za stanje S1 - Nakup.
#define S2          3   // Oznaka za stanje S2 - Prodaja.
#define S3          4   // Oznaka za stanje S4 - Zaključek.



// Globalne spremenljivke --------------------------------------------------------------------------------------------------------------------------------------------------------------
int    bpozicije [MAX_POZ][MAX_NITI]; // Enolične oznake vseh odprtih nakupnih pozicij.
int    spozicije [MAX_POZ][MAX_NITI]; // Enolične oznake vseh odprtih prodajnih pozicij.
int    stanje[MAX_NITI];              // Trenutno stanje algoritma.
int    steviloPozicij[MAX_NITI];      // Število pozicij posamezne niti.
int    verzija=1;                     // Trenutna verzija algoritma.
int    steviloNiti;                   // Trenutno število delujočih niti.
double cenaNaslednjaNitGor;           // Če je presežena ta cena se odpre nova nit
double cenaNaslednjaNitDol;           // Če je presežena ta cena se odpre nova nit
double izkupicek;                     // Izkupiček trenutne iteracije algoritma (izkupiček zaprtih pozicij, vseh niti).
double maxIzpostavljenost;            // Največja izguba algoritma (minimum od izkupickaIteracije).
double vrednostPozicij;               // Skupna vrednost vseh pozicij vseh niti, hranimo jo v spremenljivki da zmanjšamo računsko intenzivnost algoritma.
double zacetnaCena[MAX_NITI];         // Začetna cena vseh niti.



/*
****************************************************************************************************************************************************************************************
*                                                                                                                                                                                      *
* GLAVNI PROGRAM in obvezne funkcije: init, deinit, start                                                                                                                              *
*                                                                                                                                                                                      *
****************************************************************************************************************************************************************************************
*/



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: deinit  
----------------
(o) Funkcionalnost: Sistem jo pokliče ob zaustavitvi. M5 je ne uporablja
(o) Zaloga vrednosti: USPEH (vedno uspe)
(o) Vhodni parametri: /
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/   
int deinit()
{
  return( USPEH );
} // deinit 



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: init  
--------------
(o) Funkcionalnost: Sistem jo pokliče ob zagonu. V njej izvedemo naslednje:
  (-) izpišemo pozdravno sporočilo
  (-) pokličemo funkcije, ki ponastavijo vse ključne podatkovne strukture algoritma na začetne vrednosti
  (-) začnemo novo iteracijo algoritma, če je podana številka iteracije 0 ali vzpostavimo stanje algoritma glede na podano številko iteracije 
(o) Zaloga vrednosti: USPEH, NAPAKA
(o) Vhodni parametri: /
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int init()
{
  int i;           // Števec.
  double razdalja; // Izračun razdalje za stop loss.
  
  cenaNaslednjaNitDol=Ask-d; // Cena ob kateri odpremo naslednjo nit v smeri navzdol
  cenaNaslednjaNitGor=Ask+d; // Cena ob kateri odpremo naslednjo nit v smeri navzgor
  izkupicek          =0;     // Izkupiček je na začetku enak 0.
  maxIzpostavljenost =0;     // Največja izpostavljenost je na začetku enaka 0.
  steviloNiti        =1;     // Začnemo z eno nitjo   
  vrednostPozicij    =0;
  steviloPozicij[0]  =1;     // Vsaka nit ima na začetku 1 pozicijo.
  stanje[0]          =S0;    // Ponastavimo začetno stanje prve niti.
  zacetnaCena[0]     =Ask;   // Zapomnimo si začetno ceno.
  
  IzpisiPozdravnoSporocilo(); // Izpišemo pozdrav uporabniku.
  
  for( i=0; i<steviloPozicij[0]; i++ ) // Odpremo začetna nabora pozicij prve niti.
  {
    razdalja=(i+1)*d;
    bpozicije[i][0]=OdpriPozicijo( OP_BUY , Ask-razdalja);
    spozicije[i][0]=OdpriPozicijo( OP_SELL, Bid+razdalja);
  }
  
  return( USPEH );
} // init



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: start  
---------------
(o) Funkcionalnost: Glavna funkcija, ki upravlja celoten algoritem - sistem jo pokliče ob vsakem ticku. 
(o) Zaloga vrednosti: USPEH (funkcija vedno uspe)
(o) Vhodni parametri: /
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int start()
{
  int nit;            // Številka niti, ki jo trenutno obravnavamo.
  int trenutnoStanje; // Zabeležimo za ugotavljanje spremembe stanja niti.
 
  vrednostPozicij=VrednostOdprtihPozicij(); // Vrednost pozicij izračunamo tukaj namesto v stanjih vsake niti, da zmanjšamo količino računanja in pohitrimo delovanje algoritma.
  
  for( nit=0; nit<steviloNiti; nit++ ) // Izračunamo novo stanje vseh niti
  {
    trenutnoStanje = stanje[nit];
  
    switch( stanje[nit] )
    {
      case S0: stanje[nit] = S0CakanjeNaZagon(nit); break;
      case S1: stanje[nit] = S1Nakup(nit);          break;
      case S2: stanje[nit] = S2Prodaja(nit);        break;
      case S3: stanje[nit] = S3Zakljucek();      break;
      default: Print( "SuperChargerUltra-V", verzija, ":[", stevilkaIteracije, "]:nit[", nit, "]:start:OPOZORILO: Stanje ", stanje[nit], " ni veljavno stanje - preveri pravilnost delovanja algoritma." );
    }
  
    if( trenutnoStanje != stanje[nit] ) // Če je prišlo do prehoda med stanji trenutne niti, izpišemo obvestilo.
    { 
      Print( "SuperChargerUltra-V", verzija, ":[", stevilkaIteracije, "]:nit[", nit, "]:Prehod: ", ImeStanja( trenutnoStanje ), " ===========>>>>> ", ImeStanja( stanje[nit] ) ); 
    }
  } // Konec izračuna stanja vseh niti.

  if( maxIzpostavljenost > vrednostPozicij+izkupicek ) // Če se je poslabšala izpostavljenost, to zabeležimo in izpišemo obvestilo.
  { 
    maxIzpostavljenost = vrednostPozicij+izkupicek; 
    Print( ":[", stevilkaIteracije, "]:", "Nova največja izpostavljenost: ", DoubleToString( maxIzpostavljenost, 5 ) ); 
  }
    
  // Prikaz ključnih kazalnikov delovanja algoritma na zaslonu.
  Comment( "Število niti: ",              DoubleToString( steviloNiti,                        5 ), " \n",
           "Izkupiček zaprtih pozicij: ", DoubleToString( izkupicek,                          5 ), " \n",
           "Skupni izkupiček: ",          DoubleToString( izkupicek+VrednostOdprtihPozicij(), 5 ), " \n",
           "Razdalja do cilja: ",         DoubleToString( p - izkupicek,                      5 ), " \n",
           "Največja izpostavljenost: ",  DoubleToString( maxIzpostavljenost,                 5 ), " \n"
         );
         
  return( USPEH );
} // start



/*
****************************************************************************************************************************************************************************************
*                                                                                                                                                                                      *
* POMOŽNE FUNKCIJE                                                                                                                                                                     *
* Urejene po abecednem vrstnem redu                                                                                                                                                    *
****************************************************************************************************************************************************************************************
*/



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: ImeStanja( int KodaStanja )
-------------------------------------
(o) Funkcionalnost: Na podlagi numerične kode stanja, vrne opis stanja.  
(o) Zaloga vrednosti: imena stanj
(o) Vhodni parametri: KodaStanja: enolična oznaka stanja. 
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
string ImeStanja( int KodaStanja )
{
  switch( KodaStanja )
  {
    case S0: return( "S0 - ČAKANJE NA ZAGON" );
    case S1: return( "S1 - NAKUP"            );
    case S2: return( "S2 - PRODAJA"          );
    case S3: return( "S3 - ZAKLJUČEK"        );
    default: Print ( "SuperChargerUltra-V", verzija, ":[", stevilkaIteracije, "]:", ":ImeStanja:OPOZORILO: Koda stanja ", KodaStanja, 
                     " ni prepoznana. Preveri pravilnost delovanja algoritma." 
                   );
  }
  return( NAPAKA );
} // ImeStanja



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: IzkupicekZaprtihPozicij()
-----------------------------------
(o) Funkcionalnost: izračuna izkupiček vseh zaprtih pozicij vseh niti.
(o) Zaloga vrednosti: vrednost zaprtih pozicij v točkah.
(o) Vhodni parametri: številka niti.
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
double IzkupicekZaprtihPozicij( int nit )
{
  int    i;        // Števec.
  double vrednost; // Vrednost vseh pozicij podane niti.
  
  vrednost=0;
  for( i=0; i<steviloPozicij[nit]; i++ )
  {
    if( ( spozicije[i][nit] != ZAPRTA ) && ( PozicijaZaprta( spozicije[i][nit] ) == TRUE   ) ) { vrednost=vrednost+VrednostPozicije( spozicije[i][nit] ); }
    if( ( bpozicije[i][nit] != ZAPRTA ) && ( PozicijaZaprta( bpozicije[i][nit] ) == TRUE   ) ) { vrednost=vrednost+VrednostPozicije( bpozicije[i][nit] ); }
  }

  return( vrednost ); 
} // IzkupicekZaprtihPozicij



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: IzpisiPozdravnoSporocilo
----------------------------------
(o) Funkcionalnost: izpiše pozdravno sporočilo, ki vsebuje tudi verzijo algoritma
(o) Zaloga vrednosti: USPEH (funkcija vedno uspe)
(o) Vhodni parametri: /
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int IzpisiPozdravnoSporocilo()
{
  Print( "****************************************************************************************************************" );
  Print( "Dober dan. Tukaj SuperChargerMulti, verzija ", verzija, "." );
  Print( "****************************************************************************************************************" );
  return( USPEH );
} // IzpisiPozdravnoSporocilo



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: NadomestiZaprtePozicije()
---------------------------------
(o) Funkcionalnost: Nadomesti vse zaprte pozicije v poljih bpozicije in spozicije podane niti.
(o) Zaloga vrednosti: TRUE (vedno uspe).
(o) Vhodni parametri: Številka niti.
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
bool NadomestiZaprtePozicije(int nit)
{
  int i;     // Števec.
  
  for( i=0; i<steviloPozicij[nit]; i++) 
  { 
    if( ( bpozicije[i][nit] == ZAPRTA ) || ( PozicijaZaprta( bpozicije[i][nit] ) == TRUE ) ) { bpozicije[i][nit]=OdpriPozicijo( OP_BUY,  Ask-((i+1)*d) ); }
    if( ( spozicije[i][nit] == ZAPRTA ) || ( PozicijaZaprta( spozicije[i][nit] ) == TRUE ) ) { spozicije[i][nit]=OdpriPozicijo( OP_SELL, Bid+((i+1)*d) ); }
  }
  
  return( true );
} // NadomestiZaprtePozicije



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: OdpriNovoNit( int nit, int smer )
----------------------------------------------------
(o) Funkcionalnost: Odpre novo nit.
(o) Zaloga vrednosti: TRUE (vedno uspe).
(o) Vhodni parametri: 
   (-) nit: Številka niti;
   (-) smer: OP_BUY ali OP_SELL: smer v katero odpiramo nit
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
bool OdpriNovoNit( int nit, int smer )
{
  int i;           // Števec.
  double razdalja; // Izračun razdalje za stop loss pozicij.
  
  steviloPozicij[nit]=1;     // Vsaka nit ima na začetku 1 pozicijo.
  stanje[nit]        =S0;    // Ponastavimo začetno stanje prve niti.
  if( smer == OP_BUY ) { zacetnaCena[nit]=Ask; } else { zacetnaCena[nit]=Bid; }   // Zapomnimo si začetno ceno.
  
  for( i=0; i<steviloPozicij[nit]; i++ ) // Odpremo začetna nabora pozicij.
  {
    razdalja=(i+1)*d;
    bpozicije[i][nit]=OdpriPozicijo( OP_BUY , Ask-razdalja);
    spozicije[i][nit]=OdpriPozicijo( OP_SELL, Bid+razdalja);
  }
  
  Print( "SuperChargerUltra-V", verzija, ":[", stevilkaIteracije, "]:nit[", nit, "]:ODPRTA NOVA NIT" ); 
  steviloNiti++; 
  
  return( TRUE );
} // OdpriNovoNit



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: OdpriPozicijo( int Smer, double sl, int r )
----------------------------------------------------
(o) Funkcionalnost: Odpre pozicijo po trenutni tržni ceni v podani Smeri in nastavi stop loss na podano ceno
(o) Zaloga vrednosti: ID odprte pozicije;
(o) Vhodni parametri:
 (-) Smer: OP_BUY ali OP_SELL
 (-) sl: cena za stop loss
 (-) raven: raven na kateri odpiramo pozicijo
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int OdpriPozicijo( int Smer, double sl )
{
  int magicNumber; // spremenljivka, ki hrani magic number pozicije
  int rezultat;    // spremenljivka, ki hrani rezultat odpiranja pozicije
  string komentar; // spremenljivka, ki hrani komentar za pozicijo
 
  // Za primer da bi se izvajanje algoritma med izvajanjem nepričakovano ustavilo, vsako pozicijo označimo, da jo kasneje lahko prepoznamo in vzpostavimo stanje algoritma nazaj.
  magicNumber=stevilkaIteracije;
  komentar   =StringConcatenate( "SCU", verzija, "-", stevilkaIteracije );

  // Zanka v kateri odpiramo pozicije. Vztrajamo, dokler nam ne uspe.
  do
    {
      if( Smer == OP_BUY ) { rezultat = OrderSend( Symbol(), OP_BUY,  L, Ask, 0, sl, 0, komentar, magicNumber, 0, Green ); }
      else                 { rezultat = OrderSend( Symbol(), OP_SELL, L, Bid, 0, sl, 0, komentar, magicNumber, 0, Red   ); }
      if( rezultat == -1 ) 
        { 
          Print( "SuperChargerMulti-V", verzija, ":[", stevilkaIteracije, "]:", ":OdpriPozicijo:NAPAKA: neuspešno odpiranje pozicije. Ponoven poskus čez 30s..." ); 
          Sleep( 30000 );
          RefreshRates();
        }
    }
  while( rezultat == -1 );
  
  return( rezultat );
} // OdpriPozicijo



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: PozicijaZaprta( int id )
----------------------------------
(o) Funkcionalnost: Funkcija pove ali je pozicija s podanim id-jem zaprta ali ne. 
(o) Zaloga vrednosti:
 (-) true : pozicija je zaprta.
 (-) false: pozicija je odprta.
(o) Vhodni parametri: id - oznaka pozicije
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
bool PozicijaZaprta( int id )
{
  int Rezultat;
  
  Rezultat = OrderSelect( id, SELECT_BY_TICKET );
  if( Rezultat         == false ) { Print( "SuperChargerMulti-V", verzija, ":[", stevilkaIteracije, "]:", ":PozicijaZaprta:OPOZORILO: Pozicije ", id, " ni bilo mogoče najti. Preveri pravilnost delovanja algoritma." ); return( true );}
  if( OrderCloseTime() == 0     ) { return( false ); } 
  else                            { return( true );  }
} // PozicijaZaprta



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: VrednostPozicije( int id )
------------------------------------
(o) Funkcionalnost: Vrne vrednost pozicije z oznako id v točkah
(o) Zaloga vrednosti: vrednost pozicije v točkah
(o) Vhodni parametri: id - oznaka pozicije
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
double VrednostPozicije( int id )
{
  bool rezultat;
  int  vrstaPozicije;
  
  rezultat = OrderSelect( id, SELECT_BY_TICKET );
  if( rezultat == false ) 
  { 
    Print( "SuperChargerMulti-V", verzija, ":[", stevilkaIteracije, "]:", ":VrednostPozicije:NAPAKA: Pozicije ", id, 
           " ni bilo mogoče najti. Preveri pravilnost delovanja algoritma." 
         ); 
    return( 0 ); 
  }
  vrstaPozicije = OrderType();
  switch( vrstaPozicije )
  {
    case OP_BUY : if( OrderCloseTime() == 0 ) { return( Bid - OrderOpenPrice() ); } else { return( OrderClosePrice() - OrderOpenPrice()  ); }
    case OP_SELL: if( OrderCloseTime() == 0 ) { return( OrderOpenPrice() - Ask ); } else { return(  OrderOpenPrice() - OrderClosePrice() ); }
    default     : Print( "SuperChargerMulti-V", verzija, ":[", stevilkaIteracije, "]:", 
                         ":VrednostPozicije:NAPAKA: Vrsta ukaza ni ne BUY ne SELL. Preveri pravilnost delovanja algoritma." 
                       ); 
                  return( 0 );
  }
} // VrednostPozicije



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: VrednostOdprtihPozicij()
-----------------------------------
(o) Funkcionalnost: Vrne vsoto vrednosti vseh odprtih pozicij vseh niti.
(o) Zaloga vrednosti: Vsota vrednosti odprtih pozicij v točkah; 
(o) Vhodni parametri: / - uporablja globalne spremenljivke.
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
double VrednostOdprtihPozicij()
{
  int i;             // Števec.
  int nit;           // Števec niti.
  double vrednost;   // Vrednost vseh odprtih pozicij ene niti
  
  vrednost=0;
   
  // seštejemo vrednosti vseh pozicij
  for( nit=0; nit<steviloNiti; nit++ )
  {
    for( i=0; i<steviloPozicij[nit]; i++) 
    { 
      if( bpozicije[i][nit] != ZAPRTA ) { vrednost=vrednost+VrednostPozicije( bpozicije[i][nit] ); } 
      if( spozicije[i][nit] != ZAPRTA ) { vrednost=vrednost+VrednostPozicije( spozicije[i][nit] ); }
    }
  }
  
  return( vrednost );
} // VrednostOdprtihPozicij



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: ZapriPozicijo( int id )
---------------------------------
(o) Funkcionalnost: Zapre pozicijo z oznako id po trenutni tržni ceni. Če zapiranje ni bilo uspešno, počaka 5 sekund in poskusi ponovno. Če v 20 poskusih zapiranje ni uspešno, 
                    potem pošljemo sporočilo, da naj uporabnik pozicijo zapre ročno.
(o) Zaloga vrednosti:
 (-) true: če je bilo zapiranje pozicije uspešno;
 (-) false: če zapiranje pozicije ni bilo uspešno; 
(o) Vhodni parametri: id - oznaka pozicije.
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
bool ZapriPozicijo( int id )
{
  int Rezultat;     // hrani rezultate klicev OrderSelect in OrderClose
  int stevec;       // šteje število poskusov zapiranja pozicije
  string obvestilo; // hrani tekst obvestila v primeru neuspešnega zapiranja

  // poiščemo pozicijo id
  Rezultat = OrderSelect( id, SELECT_BY_TICKET );
  if( Rezultat == false ) 
    { Print( "SuperChargerMulti-V", verzija, ":[", stevilkaIteracije, "]:", ":ZapriPozicijo::NAPAKA: Pozicije ", id, " ni bilo mogoče najti. Preveri pravilnost delovanja algoritma." ); return( false ); }
  
  // pozicijo smo našli
  Rezultat = false;
  stevec   = 0;
  while( ( Rezultat == false ) && ( stevec < 20 ) )
  { 
    switch( OrderType() )
    {
      case OP_BUY : 
        Rezultat = OrderClose ( id, OrderLots(), Bid, 0, Green );
        break;
      case OP_SELL:
        Rezultat = OrderClose ( id, OrderLots(), Ask, 0, Red   );
        break;
      default: 
        return( OrderDelete( id ) );
    }
    if( Rezultat == true ) 
    { 
      Print( "SuperChargerMulti-V", verzija, ":[", stevilkaIteracije, "]:", ":LOG:ZapriPozicijo:: Pozicija ", id, " uspešno zaprta. Število poskusov: ", stevec+1 ); 
      return( true ); 
    }
    else 
    { 
      Print( "SuperChargerMulti-V", verzija, ":[", stevilkaIteracije, "]:", ":OPOZORILO:ZapriPozicijo:: Zapiranje pozicije ", id, " neuspešno. Število opravljenih poskusov: ", stevec+1 ); 
      Sleep( 5000 ); stevec++;
    }
  }
  
  // če smo prišli do sem, pomeni da tudi po 20 poskusih zapiranje ni bilo uspešno, zato pošljemo obvestilo da je potrebno pozicijo zapreti ročno
  obvestilo = "SuperChargerMulti-V" + IntegerToString( verzija ) + ":[" + IntegerToString( stevilkaIteracije ) + "]:" + Symbol() + "POMEMBNO: zapiranje pozicije ni bilo uspešno. Ročno zapri pozicijo " + IntegerToString( id );
  SendNotification( obvestilo );
  return( false );
} // ZapriPozicijo



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: ZakljuciVseNiti()
---------------------------------
(o) Funkcionalnost: Zapre vse niti.
(o) Zaloga vrednosti: true (vedno uspe).
(o) Vhodni parametri: /
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
bool ZakljuciVseNiti()
{
  int nit; // Številka trenutno obravnavane niti.
  
  for( nit=0; nit<steviloNiti; nit++) 
  {
    steviloPozicij[nit]=0;
    stanje[nit]=S3;
  }
  
  return( true );
} // ZakljuciVseNiti



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: ZapriVsePozicije()
---------------------------------
(o) Funkcionalnost: Zapre vse pozicije vseh niti.
(o) Zaloga vrednosti: true (vedno uspe).
(o) Vhodni parametri: /
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
bool ZapriVsePozicije()
{
  int i;   // Števec.
  int nit; // Številka trenutno obravnavane niti.
  
  for( nit=0; nit<steviloNiti; nit++) 
  {
    for( i=0; i<steviloPozicij[nit]; i++) 
    { 
      if( ( bpozicije[i][nit] != ZAPRTA ) && ( PozicijaZaprta( bpozicije[i][nit] ) != TRUE ) ) { ZapriPozicijo( bpozicije[i][nit] ); }
      if( ( spozicije[i][nit] != ZAPRTA ) && ( PozicijaZaprta( spozicije[i][nit] ) != TRUE ) ) { ZapriPozicijo( spozicije[i][nit] ); }
    }
  }
  
  return( true );
} // ZapriVsePozicije



/*
****************************************************************************************************************************************************************************************
*                                                                                                                                                                                      *
* FUNKCIJE DKA                                                                                                                                                                         *
*                                                                                                                                                                                      *
****************************************************************************************************************************************************************************************
*/



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA DKA: S0CakanjeNaZagon() 
--------------------------------
V to stanje vstopimo takoj ob začetku algoritma. Čakamo, da cena doseže razdaljo d nad ali pod začetno ceno (cz). Če je cena dosegla ceno cz+d, potem gremo v stanje S1Nakup, v naspro-
-tnem primeru pa v stanje S2Prodaja.
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int S0CakanjeNaZagon( int nit )
{
  
  // Preverimo ali je izpolnjen pogoj za prehod v stanje S1.
  if( PozicijaZaprta( spozicije[0][nit] ) == TRUE ) 
  { 
    return( S1 );
  }
  
  // Preverimo ali je izpolnjen pogoj za prehod v stanje S2.
  if( PozicijaZaprta( bpozicije[0][nit] ) == TRUE ) 
  { 
    return( S2 );
  }
  
  // Če nobeno pogoj za prehod ni izpolnjen, ostanemo v stanju S0.
  return( S0 );
  
} // S0CakanjeNaZagon



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA DKA: S1Nakup()
-----------------------
Cena je nad začetno ceno cz. Čakamo, da cena napreduje naprej v smeri BUY dokler ni dosežen profitni cilj. Ko se to zgodi, gremo v stanje S3. Če se cena vrne nazaj do začetne cene, se
vrnemo v stanje S0, še prej pa zabeležimo izkupiček zaprtih pozicij.
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int S1Nakup( int nit )
{ 
  if( vrednostPozicij+izkupicek > p ) // Preverimo ali je izpolnjen pogoj za prehod v stanje S3 - dosežen profitni cilj.
  { 
    ZapriVsePozicije();
    ZakljuciVseNiti();
    return( S3 );
  }
  
  if( Bid <= zacetnaCena[nit] ) // Preverimo ali je izpolnjen pogoj za prehod v stanje S0.
  {
    izkupicek=izkupicek+IzkupicekZaprtihPozicij( nit );
    bpozicije[steviloPozicij[nit]][nit]=ZAPRTA;
    spozicije[steviloPozicij[nit]][nit]=ZAPRTA;
    steviloPozicij[nit]++;
    NadomestiZaprtePozicije( nit );
    return( S0 );
  }

  if( Ask >= cenaNaslednjaNitGor ) // Odpremo novo nit
  {
    OdpriNovoNit( steviloNiti, OP_BUY );
    cenaNaslednjaNitGor=cenaNaslednjaNitGor+d;
  }
  return( S1 ); // V nasprotnem primeru ostanemo v stanju S1.
} // S1Nakup



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA DKA: S2Prodaja()
-----------------------
Cena je pod začetno ceno cz. Čakamo, da cena napreduje naprej v smeri SELL dokler ni dosežen profitni cilj. Ko se to zgodi, gremo v stanje S3. Če se cena vrne nazaj do začetne cene, 
se vrnemo v stanje S0, še prej pa zabeležimo izkupiček zaprtih pozicij.
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int S2Prodaja( int nit )
{ 
  if( VrednostOdprtihPozicij()+izkupicek > p ) // Preverimo ali je izpolnjen pogoj za prehod v stanje S3 - dosežen profitni cilj.
  { 
    ZapriVsePozicije();
    ZakljuciVseNiti();
    return( S3 );
  }
  
  if( Ask >= zacetnaCena[nit] ) // Preverimo ali je izpolnjen pogoj za prehod v stanje S0.
  {
    izkupicek=izkupicek+IzkupicekZaprtihPozicij( nit );
    bpozicije[steviloPozicij[nit]][nit]=ZAPRTA;
    spozicije[steviloPozicij[nit]][nit]=ZAPRTA;
    steviloPozicij[nit]++;
    NadomestiZaprtePozicije( nit );
    return( S0 );
  }

  if( Bid <= cenaNaslednjaNitDol ) // Odpremo novo nit
  {
    OdpriNovoNit( steviloNiti, OP_SELL );
    cenaNaslednjaNitDol=cenaNaslednjaNitDol-d;
  }
  return( S2 ); // V nasprotnem primeru ostanemo v stanju S2.
} // S2Prodaja



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA DKA: S3Zakljucek()
V tem stanju se znajdemo, ko je bil dosežen profitni cilj. Če je vrednost parametra samodejni zagon enaka NE, potem v tem stanju ostanemo, dokler uporabnik ročno ne prekine delovanja 
algoritma. Če je vrednost parametra samodejni zagon enaka DA, potem ustrezno ponastavimo stanje algoritma in ga ponovno poženemo.
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int S3Zakljucek()
{ 
  if( samodejniPonovniZagon > 0 ) { init(); stevilkaIteracije++; return( S0 ); } else { return( S3 ); }
} // S3Zakljucek
