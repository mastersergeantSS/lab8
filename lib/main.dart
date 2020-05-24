import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_map_polyutil/gmp.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' show get;
import 'package:flutter/services.dart';

Set<Polyline> polylines;
Position initialPosition;
String origin, destination;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(MyApp());
} 


class MyApp extends StatelessWidget {
  final originController = TextEditingController();
  final destinationController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      routes: {
        '/': (context) => SafeArea(
          child: Scaffold(
            body: DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: TabBar(
                  labelColor: Colors.black,
                  indicatorColor: Colors.black,
                  tabs: <Tab>[
                    Tab(text: 'Откуда'),
                    Tab(text: 'Куда'),
                  ],
                ),
                body: TabBarView(
                  children: List<Widget>.generate(2, (index) => ListPlaces(index == 0 ? originController : destinationController, index)),
                ),
              ),
            ),
            floatingActionButton: FloatingActionButton(
              backgroundColor: Colors.red,
              onPressed: () async {
                try {
                  initialPosition = await Geolocator().getCurrentPosition();
                  origin = Uri.encodeFull(originController.text);
                  destination = Uri.encodeFull(destinationController.text);
                  Navigator.pushNamed(context, 'result');
                }
                catch (e) {}
              },
              child: Icon(Icons.search),
            ),
          ),
        ),
        'result': (context) => Map(),
      },
      initialRoute: '/',
    );
  }
}


class ListPlaces extends StatefulWidget{
  final TextEditingController searchController;
  ListPlaces(this.searchController, int index) : super(key: ValueKey(index));
  @override
  State<ListPlaces> createState() => ListPlacesState();
}


class ListPlacesState extends State<ListPlaces> with AutomaticKeepAliveClientMixin<ListPlaces> {
  final mapController = Completer<GoogleMapController>();
  Set<Marker> markers = {};
  List places = [];

  @override
  bool get wantKeepAlive => true;

  @override void initState() {
    widget.searchController.addListener(() async {
      if (widget.searchController.text != null && widget.searchController.text != '') {
        places = jsonDecode((await get(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeFull(widget.searchController.text)}&language=ru&key=AIzaSyD4I4HZ25lHy9WftOj4x3fEKCoEGYmJHgk'
        )).body)['predictions'];
        setState(() {});
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: widget.searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            contentPadding: EdgeInsets.only(left: 20),
            hintText: 'Поиск',
          ),
        ),
        if (places.length != 0) Container(
          constraints: BoxConstraints(maxHeight: min(147, places.length * 49.0)),
          child: CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
              sliver: SliverFixedExtentList(
                itemExtent: 49,
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: <Widget>[
                        ListTile(
                          title: Text(places[index]['description'], maxLines: 2),
                          dense: true,
                          onTap: () async {
                            final place = jsonDecode((await get(
                              'https://maps.googleapis.com/maps/api/place/details/json?place_id=${places[index]['place_id']}&key=AIzaSyD4I4HZ25lHy9WftOj4x3fEKCoEGYmJHgk'
                            )).body)['result']['geometry']['location'];
                            final position = LatLng(place['lat'], place['lng']);
                            final controller = await mapController.future;
                            setState(() {
                              markers.add(Marker(
                                markerId: MarkerId('0'),
                                position: position,
                              ));
                              // initialCameraPosition = ;
                              controller.moveCamera(CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: position,
                                  zoom: 15,
                                )
                              ));
                            });
                          },
                        ),
                        Divider(
                          color: Colors.black, 
                          height: 1,
                        ),
                      ],
                    );
                  },
                  childCount: places.length,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GoogleMap(
            zoomControlsEnabled: false,
            markers: markers,
            myLocationButtonEnabled: false,
            initialCameraPosition: CameraPosition(
              target: LatLng(37.42796133580664, -122.085749655962),
              zoom: 14.4746,
            ),
            onMapCreated: (GoogleMapController controller) {
              if (!mapController.isCompleted) {
                mapController.complete(controller);
              }
            },
          )
        ),
      ],
    );
  }
}


class Map extends StatefulWidget {
  @override
  State<Map> createState() => MapState();
}


class MapState extends State<Map> {
  bool failed = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        GoogleMap(
          zoomControlsEnabled: false,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          polylines: polylines,
          initialCameraPosition: CameraPosition(
            target: LatLng(initialPosition.latitude, initialPosition.longitude),
            zoom: 12,
          ),
          onMapCreated: (GoogleMapController controller) async {
            polylines = {};
            try {
              final response = await get('https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=AIzaSyD4I4HZ25lHy9WftOj4x3fEKCoEGYmJHgk');
              final route = jsonDecode(response.body)['routes'][0];
              final upperRightCorner = route['bounds']['southwest'];
              final bottomLeftCorner = route['bounds']['northeast'];
              if (initialPosition.latitude < upperRightCorner['lat']) {
                upperRightCorner['lat'] = initialPosition.latitude;
              }
              else if (initialPosition.latitude > bottomLeftCorner['lat']) {
                bottomLeftCorner['lat'] = initialPosition.latitude;
              }
              if (initialPosition.longitude < upperRightCorner['lng']) {
                upperRightCorner['lng'] = initialPosition.longitude;
              }
              else if (initialPosition.longitude > bottomLeftCorner['lng']) {
                bottomLeftCorner['lng'] = initialPosition.longitude;
              }
              final points = await GMP.decode(route['overview_polyline']['points']);
              polylines = {Polyline(
                polylineId: PolylineId('0'),
                points: points,
                consumeTapEvents: false,
                color: Colors.black,
                width: 4,
              )};
              if (points.length > 1) {
                setState(() {
                  controller.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(
                      southwest: LatLng(upperRightCorner['lat'], upperRightCorner['lng']), 
                      northeast: LatLng(bottomLeftCorner['lat'], bottomLeftCorner['lng']),
                    ), 
                    20.0,
                  ));
                });
              }
            }
            catch (e) {
              setState(() {
                failed = true;
              });
            }
          },
        ),
        if (failed) Align(child: Text('Not Found')),
      ],
    );
  }
}
