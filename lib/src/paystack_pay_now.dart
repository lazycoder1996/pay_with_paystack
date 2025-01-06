// ignore_for_file: prefer_typing_uninitialized_variables, use_build_context_synchronously

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pay_with_paystack/model/payment_data.dart';
import 'package:pay_with_paystack/model/paystack_request_response.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaystackPayNow extends StatefulWidget {
  final String secretKey;
  final String reference;
  final String? callbackUrl;
  final String? currency;
  final String email;
  final double amount;
  final String? plan;
  final metadata;
  final paymentChannel;
  final void Function(PaymentData data)? transactionCompleted;
  final void Function(String reason)? transactionNotCompleted;

  const PaystackPayNow({
    Key? key,
    required this.secretKey,
    required this.email,
    required this.reference,
    this.currency = 'USD',
    required this.amount,
    this.callbackUrl,
    this.transactionCompleted,
    this.transactionNotCompleted,
    this.metadata,
    this.plan,
    this.paymentChannel,
  }) : super(key: key);

  @override
  State<PaystackPayNow> createState() => _PaystackPayNowState();
}

class _PaystackPayNowState extends State<PaystackPayNow> {
  /// Makes HTTP Request to Paystack for access to make payment.
  Future<PaystackRequestResponse> _makePaymentRequest() async {
    http.Response? response;
    final amount = widget.amount * 100;

    try {
      /// Sending Data to paystack.
      response = await http.post(
        /// Url to send data to
        Uri.parse('https://api.paystack.co/transaction/initialize'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.secretKey}',
        },

        /// Data to send to the URL.
        body: jsonEncode({
          "email": widget.email,
          "amount": amount.toString(),
          "reference": widget.reference,
          "currency": widget.currency,
          "plan": widget.plan,
          "metadata": widget.metadata,
          "callback_url": widget.callbackUrl,
          "channels": widget.paymentChannel
        }),
      );
    } on Exception catch (e) {
      /// In the event of an exception, take the user back and show a SnackBar error.
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        var snackBar =
            SnackBar(content: Text("Fatal error occurred, ${e.toString()}"));
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    }

    if (response!.statusCode == 200) {
      return PaystackRequestResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception(
          "Response Code: ${response.statusCode}, Response Body${response.body}");
    }
  }

  /// Checks for transaction status of current transaction before view closes.
  Future _checkTransactionStatus(String ref) async {
    http.Response? response;
    try {
      /// Getting data, passing [ref] as a value to the URL that is being requested.
      response = await http.get(
        Uri.parse('https://api.paystack.co/transaction/verify/$ref'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.secretKey}',
        },
      );
    } on Exception catch (_) {
      /// In the event of an exception, take the user back and show a SnackBar error.
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        var snackBar = const SnackBar(
            content: Text("Fatal error occurred, Please check your internet"));
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    }
    if (response!.statusCode == 200) {
      var decodedRespBody = jsonDecode(response.body);
      // print(decodedRespBody.toString());
      if (decodedRespBody["data"]["status"] == "success") {
        final data = PaymentData.fromJson(decodedRespBody["data"]);
        widget.transactionCompleted?.call(data);
      } else {
        widget.transactionNotCompleted
            ?.call(decodedRespBody["data"]["status"].toString());
      }
    } else {
      /// Anything else means there is an issue
      throw Exception(
          "Response Code: ${response.statusCode}, Response Body${response.body}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: FutureBuilder<PaystackRequestResponse>(
        future: _makePaymentRequest(),
        builder: (context, AsyncSnapshot<PaystackRequestResponse> snapshot) {
          /// Show screen if snapshot has data and status is true.
          if (snapshot.hasData && snapshot.data!.status == true) {
            final controller = WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              // ..setUserAgent("Flutter;Webview")
              ..setNavigationDelegate(
                NavigationDelegate(
                  onNavigationRequest: (request) async {
                    if (request.url.contains('cancelurl.com')) {
                      await _checkTransactionStatus(snapshot.data!.reference)
                          .then((value) {
                        Navigator.of(context).pop();
                      });
                    }
                    if (request.url.contains('paystack.co/close')) {
                      await _checkTransactionStatus(snapshot.data!.reference)
                          .then((value) {
                        Navigator.of(context).pop();
                      });
                    }
                    if (request.url.contains(widget.callbackUrl ?? '')) {
                      await _checkTransactionStatus(snapshot.data!.reference)
                          .then((value) {
                        Navigator.of(context).pop();
                      });
                    }
                    return NavigationDecision.navigate;
                  },
                ),
              )
              ..loadRequest(Uri.parse(snapshot.data!.authUrl));
            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                actions: [
                  InkWell(
                      onTap: () async {
                        await _checkTransactionStatus(snapshot.data!.reference)
                            .then((value) {
                          Navigator.of(context).pop();
                        });
                      },
                      child: const Icon(Icons.close)),
                ],
              ),
              body: WebViewWidget(
                controller: controller,
              ),
            );
          }

          if (snapshot.hasError) {
            return Material(
              child: Center(
                child: Text('${snapshot.error}'),
              ),
            );
          }

          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      ),
    );
  }
}
